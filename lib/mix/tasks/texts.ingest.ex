defmodule Mix.Tasks.Texts.Ingest do
  use Mix.Task

  @shortdoc "Ingests cloned repositories of XML and JSON texts."

  @moduledoc """
  This task ingests the following repositories:

  #{TextServer.Texts.repositories() |> Enum.map_join("\n", & &1[:url])}
  """

  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("... Ingesting repositories ... \n")

    ingest_repos()

    Mix.shell().info("... Finished ingesting repositories ... ")
  end

  def collection_urn(url) do
    String.split(url, "/")
    |> List.last()
    |> String.replace(Path.extname(url), "")
    |> Recase.to_camel()
  end

  def get_filename_from_path(s) do
    path_prefix = Path.expand(System.get_env("TEXT_REPO_DESTINATION", "tmp"))

    String.replace_prefix(s, "#{path_prefix}/", "")
  end

  def get_ref_levels_from_tei_header(header_data) do
    ref_state_units =
      header_data
      |> Enum.filter(fn d -> Map.get(d, :tag_name) == "refState" end)
      |> Enum.map(fn r ->
        Map.get(r, :attributes)
        |> Enum.find_value(fn a ->
          if elem(a, 0) == "unit" do
            elem(a, 1)
          end
        end)
      end)
      |> Enum.reverse()

    units =
      unless Enum.empty?(ref_state_units) do
        ref_state_units
      else
        cref =
          header_data
          |> Enum.filter(fn d -> Map.get(d, :tag_name) == "cRefPattern" end)
          |> List.first()

        attrs = Map.get(cref || %{}, :attributes)

        Enum.find_value(attrs || [], fn a ->
          if elem(a, 0) == "n" do
            [elem(a, 1)]
          end
        end)
      end

    if is_nil(units) do
      ["line"]
    else
      units
    end
  end

  def get_content_from_tag(data, tag) do
    Enum.find_value(data, fn d ->
      if d[:current_tag] == tag do
        d[:content]
      end
    end)
  end

  def parse_exemplar_xml(f) do
    Mix.shell().info("Ingesting exemplar XML at #{f}")

    file_stream = File.stream!(f)

    header_data =
      case Saxy.parse_stream(file_stream, Xml.ExemplarHeaderHandler, {nil, []}) do
        {:ok, data} -> data
        {:error, _reason} -> nil
      end

    _exemplar =
      if is_nil(header_data) do
        nil
      else
        ref_levels = get_ref_levels_from_tei_header(header_data)

        language_id =
          Enum.find_value(header_data, fn d ->
            attrs = Map.new(d[:attributes])
            lang = Enum.find(attrs, fn a -> elem(a, 0) == "xml:lang" end)

            unless is_nil(lang) do
              language = TextServer.Languages.get_by_slug(elem(lang, 1))
              language.id
            else
              IO.inspect("Could not find language for slug #{lang}. Defaulting to English.")
              language = TextServer.Languages.get_by_slug("en")
              language.id
            end
          end)

        body_data =
          case Saxy.parse_stream(file_stream, Xml.ExemplarBodyHandler, %{ref_levels: ref_levels}) do
            {:ok, data} -> data
            {:error, _reason} -> nil
          end

        %{
          body: body_data,
          filemd5hash:
            :crypto.hash(:md5, Enum.to_list(file_stream)) |> Base.encode16(case: :lower),
          filename: f,
          header: header_data,
          structure: Enum.join(ref_levels || ["line"], "."),
          language_id: language_id,
          title: get_content_from_tag(header_data, :title),
          tei_header: %{
            file_description: %{
              date: get_content_from_tag(header_data, :date),
              editor: get_content_from_tag(header_data, :title),
              principal: get_content_from_tag(header_data, :principal),
              publisher: get_content_from_tag(header_data, :publisher),
              publication_place: get_content_from_tag(header_data, :publication_placer),
              responsibility:
                Enum.filter(header_data, fn d ->
                  d[:current_tag] == :name
                end)
                |> Enum.map(fn d -> d[:content] end),
              sponsor: get_content_from_tag(header_data, :sponsor)
            },
            profile_description: %{},
            revision_description: %{
              changes:
                Enum.filter(header_data, fn d -> d[:current_tag] == :change end)
                |> Enum.map(fn d ->
                  %{attributes: Map.new(d[:attributes]), description: d[:content]}
                end)
            }
          }
        }
      end
  end

  defp parse_text_group_cts(f, collection) do
    Mix.shell().info("Ingesting text_group CTS at #{f}")

    stream = File.stream!(f)
    {:ok, data} = Saxy.parse_stream(stream, Xml.TextGroupCtsHandler, %{})

    %{
      collection_id: collection.id,
      title: data[:groupname],
      urn: data[:urn],
      language: data[:language]
    }
  end

  defp parse_work_xml(f) do
    Mix.shell().info("Ingesting work CTS at #{f}")

    stream = File.stream!(f)
    {:ok, cts_data} = Saxy.parse_stream(stream, Xml.WorkCtsHandler, {nil, []})

    cts_data
  end

  defp ingest_json_collection(f, collection) do
    filename = get_filename_from_path(f)

    Mix.shell().info("Ingesting #{filename}")

    [_text_group_fragment, work_fragment, language_fragment] =
      String.split(filename, ".")
      |> List.first()
      |> String.split("__")

    {:ok, binary} = File.read(f)
    {:ok, parsed} = Jason.decode(binary)

    # NOTE: (charles) For many of these texts, "author" is "Not available". Is
    # this actually what we want in our URNs?
    text_group_title =
      case parsed["author"] do
        "" -> "unknown"
        "(Original Book)" -> "original book"
        "Not available" -> "unknown"
        _ -> parsed["author"]
      end

    {:ok, text_group} =
      TextServer.TextGroups.find_or_create_text_group(%{
        collection_id: collection.id,
        title: text_group_title,
        urn: "#{collection.urn}:#{Recase.to_camel(text_group_title)}"
      })

    {:ok, language} =
      TextServer.Languages.find_or_create_language(%{title: String.downcase(parsed["language"])})

    work_urn = "#{text_group.urn}.#{Recase.to_camel(work_fragment)}"
    english_title = parsed["englishTitle"] || text_group.title
    original_title = parsed["originalTitle"]
    description = parsed["description"]

    {:ok, work} =
      TextServer.Works.find_or_create_work(%{
        description: description,
        english_title: english_title,
        original_title: original_title,
        urn: work_urn,
        text_group_id: text_group.id
      })

    # NOTE: (charles) The Middle English texts (so far) are not very
    # well organized. The data itself appears to be mostly fine, but
    # they're missing titles (Piers Plowman was, at least) or have titles
    # that are way too long.

    version_attrs =
      case parsed do
        %{
          "edition" => edition,
          "source" => "The Center for Hellenic Studies",
          "language" => "english"
        } ->
          %{
            label: edition,
            urn: "#{work.urn}.chs-translation",
            version_type: :translation,
            work_id: work.id
          }

        %{"edition" => edition, "source" => "The Center For Hellenic Studies"} ->
          %{
            label: edition,
            urn: "#{work.urn}.chs-#{Recase.to_camel(edition)}",
            version_type: :edition,
            work_id: work.id
          }

        %{"edition" => edition} ->
          %{
            label: edition,
            urn: "#{work.urn}.#{Recase.to_camel(language_fragment)}",
            version_type: :edition,
            work_id: work.id
          }

        _ ->
          %{
            label: original_title || english_title,
            urn: "#{work.urn}.#{Recase.to_camel(language_fragment)}",
            version_type: :edition,
            work_id: work.id
          }
      end

    {:ok, version} = TextServer.Versions.find_or_create_version(version_attrs)

    source = parsed["source"]
    source_link = parsed["sourceLink"]

    {:ok, exemplar} =
      TextServer.Exemplars.find_or_create_exemplar(%{
        description: description,
        filename: filename,
        filemd5hash: :crypto.hash(:md5, binary) |> Base.encode16(case: :lower),
        form: nil,
        label: nil,
        language_id: language.id,
        title: original_title || english_title,
        source: source,
        source_link: source_link,
        structure: nil,
        urn: "#{version.urn}.#{Recase.to_camel(source)}",
        version_id: version.id
      })

    Iteraptor.to_flatmap(parsed["text"])
    |> Enum.map(fn {k, v} ->
      location = String.split(k, ".") |> Enum.map(&String.to_integer/1)

      TextServer.TextNodes.find_or_create_text_node(%{
        location: location,
        text: v,
        exemplar_id: exemplar.id
      })
    end)

    f
  end

  defp ingest_json(dir, collection) do
    Mix.shell().info("... Ingesting JSON-based texts in #{dir} ... \n")

    ingested_files =
      Path.wildcard("#{dir}/*.json")
      |> Stream.map(fn f -> ingest_json_collection(f, collection) end)
      |> Enum.to_list()

    Mix.shell().info(
      "... Finished ingesting the following JSON files: ... \n #{inspect(ingested_files)}"
    )
  end

  defp ingest_xml(dir, collection) do
    Mix.shell().info("... Ingesting XML-based texts in: #{dir} ... \n")

    file_queue = TextServer.Ingestion.list_ingestion_items_in_collection(collection.id)

    xml_files =
      if Enum.count(file_queue) == 0 do
        Path.wildcard("#{dir}/**/*.xml")
      else
        file_queue |> Enum.map(fn f -> f.path end)
      end

    cts_files =
      xml_files
      |> Stream.filter(fn f -> String.ends_with?(f, "__cts__.xml") end)
      |> Enum.reduce(%{text_group_files: [], work_files: []}, fn f, acc ->
        update =
          if String.split(f, "/data/") |> List.last() |> Path.split() |> Enum.count() < 3 do
            :text_group_files
          else
            :work_files
          end

        Map.update(acc, update, [f], &[f | &1])
      end)

    text_groups_data =
      Stream.map(cts_files[:text_group_files], &parse_text_group_cts(&1, collection))

    works_data = Stream.map(cts_files[:work_files], &parse_work_xml/1)

    _text_groups =
      text_groups_data
      |> Enum.map(fn tg ->
        TextServer.Languages.find_or_create_language(%{title: Map.get(tg, :language)})
        TextServer.TextGroups.find_or_create_text_group(Map.delete(tg, :language))
      end)

    TextServer.Ingestion.delete_all_items_by_paths(cts_files[:text_group_files])

    works_and_versions = create_works_and_versions(works_data, collection)

    TextServer.Ingestion.delete_all_items_by_paths(cts_files[:work_files])

    versions =
      Stream.flat_map(works_and_versions || [], fn wvs -> Map.get(wvs, :versions, []) end)

    versions =
      if Enum.count(versions) == 0 do
        TextServer.Versions.list_versions_in_collection(collection.id)
      else
        versions
      end

    _exemplars =
      Enum.map(versions, fn v ->
        urn = String.split(v.urn, ":") |> List.last()
        ingestion_exemplars = TextServer.Ingestion.list_ingestion_items_like("%#{urn}.xml")

        ingestion_exemplars
        |> Enum.map(fn ex ->
          f = ex.path
          exemplar_data = parse_exemplar_xml(f)

          exemplar =
            if is_nil(exemplar_data) do
              IO.inspect("Unable to parse exemplar file #{f}")
              nil
            else
              ex_data =
                Map.merge(
                  Map.delete(exemplar_data, :body),
                  %{description: v.description, label: v.label, urn: v.urn, version_id: v.id}
                )

              {:ok, exemplar} = TextServer.Exemplars.find_or_create_exemplar(ex_data)
              exemplar
            end

          # NOTE: (charles) This is admittedly a bit confusing. "elems" here
          # refers to anything contained in an exemplar's body, including
          # TextNodes. TextNodes are differentiated from TextElements by
          # containing a :content key.
          _text_elements =
            unless is_nil(exemplar) do
              elems = exemplar_data[:body][:text_elements]

              if is_nil(elems) do
                IO.inspect("No text elements? #{inspect(exemplar_data[:body])}")
                []
              else
                process_exemplar_text_nodes(
                  exemplar,
                  Enum.filter(elems, fn el -> Map.has_key?(el, :content) end)
                )

                process_exemplar_text_elements(exemplar, elems)
              end
            end

          TextServer.Ingestion.delete_item(ex)
          ex
        end)
      end)
  end

  defp process_exemplar_text_elements(exemplar, data) do
    data
    |> Enum.group_by(fn el -> el[:tag_name] end)
    |> Enum.each(fn {_k, v} ->
      [starts, ends] =
        case Enum.group_by(v, fn x -> Map.has_key?(x, :start) end) do
          %{true: starts, false: ends} -> [starts, ends]
          %{true: starts} -> [starts, []]
          %{false: ends} -> [[], ends]
        end

      indexed_starts = Enum.with_index(starts)

      indexed_starts
      |> Enum.each(fn {start, i} ->
        matching_end =
          case Enum.fetch(ends, i) do
            {:ok, e} ->
              e

            :error ->
              IO.inspect(
                "No matching end node found! Index: #{i}\n#{inspect(start)}\nExemplar ID: #{exemplar.id}"
              )

              nil
          end

        element_type =
          case TextServer.ElementTypes.find_or_create_element_type(%{name: start[:tag_name]}) do
            {:ok, element_type} ->
              element_type

            {:error, reason} ->
              IO.inspect("There was an error finding or creating an ElementType: #{reason}")
              nil
          end

        end_node =
          TextServer.TextNodes.get_by(%{
            exemplar_id: exemplar.id,
            location: matching_end[:location]
          })

        start_node =
          TextServer.TextNodes.get_by(%{exemplar_id: exemplar.id, location: start[:location]})

        unless is_nil(start_node) or is_nil(end_node) do
          TextServer.TextElements.find_or_create_text_element(%{
            attributes: start[:attributes],
            element_type_id: element_type.id,
            end_offset: matching_end[:offset] || 0,
            end_text_node_id: end_node.id,
            start_offset: start[:offset] || 0,
            start_text_node_id: start_node.id
          })
        end
      end)
    end)
  end

  defp process_exemplar_text_nodes(exemplar, nodes) do
    Enum.each(nodes, fn el ->
      TextServer.TextNodes.find_or_create_text_node(%{
        exemplar_id: exemplar.id,
        location: el[:location],
        text: el[:content]
      })
    end)
  end

  defp create_works_and_versions(data, collection) do
    data
    |> Enum.map(fn ws ->
      saved_works =
        Enum.filter(ws, &Map.has_key?(&1, :text_group_urn))
        |> Enum.map(fn w ->
          text_group = TextServer.TextGroups.get_by_urn(Map.get(w, :text_group_urn))
          work_attrs = Map.take(w, Map.keys(TextServer.Works.Work.__struct__()))

          if text_group != nil do
            TextServer.Works.find_or_create_work(
              Map.put(work_attrs, :text_group_id, text_group.id)
            )
          else
            text_group =
              TextServer.TextGroups.find_or_create_text_group(%{
                collection_id: collection.id,
                title: "Orphaned Work Parent Group",
                urn: w[:text_group_urn]
              })

            {:ok, work} =
              TextServer.Works.find_or_create_work(
                Map.put(work_attrs, :text_group_id, text_group.id)
              )

            work
          end
        end)

      saved_versions =
        Enum.filter(ws, &Map.has_key?(&1, :work_urn))
        |> Enum.map(fn v ->
          work = TextServer.Works.get_by_urn(Map.get(v, :work_urn))

          version_attrs =
            Map.take(v, Map.keys(TextServer.Versions.Version.__struct__()))
            |> Map.put(:work_id, work.id)

          {:ok, version} = TextServer.Versions.find_or_create_version(version_attrs)
          version
        end)

      %{versions: saved_versions, works: saved_works}
    end)
  end

  defp ingest_repo(repo) do
    %{title: title, url: url} = repo
    dir = Path.expand(System.get_env("TEXT_REPO_DESTINATION", "./tmp"))

    repo_dir_name =
      String.split(url, "/")
      |> List.last()
      |> String.replace(".git", "")

    dest = Path.join(dir, repo_dir_name) |> Path.expand("./")
    urn = Map.get(repo, :urn) || "urn:cts:#{collection_urn(url)}"

    collection_attrs = %{
      repository: url,
      title: title,
      urn: urn
    }

    {:ok, collection} = TextServer.Collections.find_or_create_collection(collection_attrs)

    if File.dir?(json_dir = Path.join(dest, "cltk_json")) do
      ingest_json(json_dir, collection)
    else
      ingest_xml(Path.join(dest, "data"), collection)
    end
  end

  defp ingest_repos() do
    TextServer.Texts.repositories()
    |> Stream.map(&ingest_repo/1)
    |> Enum.to_list()
  end
end
