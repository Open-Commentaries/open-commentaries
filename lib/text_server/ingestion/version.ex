defmodule TextServer.Ingestion.Version do
  alias TextServer.TextElements
  alias TextServer.TextNodes
  alias TextServer.Versions
  alias TextServer.Versions.Version

  require Logger

  @location_regex ~r/\{\d+\.\d+\.\d+\}/

  # the @attribution_regex is a special case for matching
  # old comments by Greg Nagy ("GN") that have been
  # manually attributed. Normally, attribution will come
  # directly from a comment's XML.
  @attribution_regex ~r/\[\[GN\s(\d{4}\.\d{2}\.\d{2})\]\]/

  def clear_text_nodes(%Version{} = version) do
    TextNodes.delete_text_nodes_by_version_id(version.id)
  end

  def parse_version(%Version{} = version) do
    clear_text_nodes(version)

    case Path.extname(version.filename) do
      ".docx" -> parse_version_docx(version)
      # ".xml" -> queue_version_for_external_parsing(version)
      _ -> raise "Unable to parse version #{version.filename}"
    end

    Versions.update_version(version, %{parsed_at: NaiveDateTime.utc_now()})
  end

  # pandoc: /app/data/user_uploads/exemplar_files/GN_A Pausanias reader in progress, restarted 2020.05.01(1)-Gipson-6-18-2022.docx
  def parse_version_docx(%Version{} = version) do
    # `track_changes: "all"` catches comments; see example below
    {:ok, ast} =
      Panpipe.ast(
        input: version.filename,
        extract_media: version.urn,
        track_changes: "all"
      )

    # We should be able to transform the AST into a collection
    # of text nodes, even when we have paragraphs (like
    # poetry or bulleted lists) that break our assumptions about
    # how to locate elements.
    # Why not use the AST transformation to tag locations, as well as:
    # - TODO: join "orphaned" nodes to the previously seen location
    #   - could we use ETS for this? https://elixir-lang.org/getting-started/mix-otp/ets.html
    # - TODO: convert to markdown with locations stored in text_nodes

    fragments = collect_fragments(ast)
    # we need to keep track of location fragments that have been seen and use
    # the last-seen fragment in cases where the location gets zeroed out
    {_last_loc, located_fragments} =
      fragments
      |> Enum.reduce({[0], %{}}, &set_locations/2)

    joined_fragments =
      located_fragments
      |> Enum.map(fn {location, fragments} ->
        serialize_fragments(location, fragments)
      end)

    nodes =
      joined_fragments
      |> Enum.map(fn {location, text, elements} ->
        {:ok, text_node} =
          TextNodes.find_or_create_text_node(%{
            version_id: version.id,
            location: location,
            text: text,
            urn: "#{version.urn}:#{Enum.join(location, ".")}"
          })

        _elements_and_errors = TextElements.find_or_create_text_elements(text_node, elements)

        {:ok, text_node}
      end)

    {:ok, nodes}
  end

  def set_locations({:paragraph, fragments}, state) do
    {loc, located_fragments} = set_locations(fragments, state)
    # So far, it seems to work well to treat paragraphs
    # as simply two newlines, like in Markdown.
    {loc,
     Map.update(located_fragments, loc, [], fn v ->
       # Don't add a paragraph break at the beginning of a
       # TextNode
       if Enum.empty?(v) do
         v
       else
         v ++ [{:string, "\n\n"}]
       end
     end)}
  end

  def set_locations(fragments, {prev_location, grouped_frags}) do
    [loc | frags] = set_location(prev_location, fragments)

    current_fragments = Map.get(grouped_frags, loc, [])

    # As far as I can tell, the call to List.flatten/1, although
    # it seems redundant, is necessary to ensure that we can
    # concatenate the lists successfully.
    updated_frags = current_fragments ++ List.flatten([frags])

    {loc, Map.put(grouped_frags, loc, updated_frags)}
  end

  def set_location(prev_location, list) when is_list(list) do
    [maybe_location_fragment | rest] = list

    maybe_location_string = get_maybe_location_string(maybe_location_fragment) || ""

    location =
      case Regex.run(@location_regex, maybe_location_string) do
        regex_list when is_list(regex_list) ->
          parse_location_marker(regex_list)

        nil ->
          [0]
      end

    if prev_location != [0] and location == [0] do
      # note that we return the entire list here so we don't
      # accidentally pop off important elements
      [prev_location | list]
    else
      [location | rest]
    end
  end

  # FIXME: This is a cludge for handling bulleted lists -- it won't
  # end up displaying the lists correctly.
  def set_location(prev_location, {:bullet_list, list}) do
    [prev_location | list]
  end

  def get_maybe_location_string(fragment) do
    case fragment do
      {:string, string} ->
        string

      {_, maybe_list} when is_list(maybe_list) ->
        maybe_list |> Enum.find_value(&get_maybe_location_string/1)

      _ ->
        false
    end
  end

  defp parse_location_marker(regex_list) do
    List.first(regex_list)
    |> String.replace("{", "")
    |> String.replace("}", "")
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  @doc """
  FIXME: (charles)

  Bugs:
  - bullet_lists are not handled properly
  - poetry is not handled properly

  For examples, see especially Pausanias 5.10
  """
  def serialize_fragments(location, fragments) do
    text =
      fragments
      |> Enum.reduce("", &flatten_string/2)

    # if getting the location has left the node starting with a single space,
    # pop that element off the node entirely. This helps to avoid off-by-one
    # errors in offsets. An assumption is made that a node that begins with
    # more than a single space character does so for a reason, so we maintain
    # that string
    fragments =
      if List.first(fragments) == {:string, " "} do
        tl(fragments)
      else
        fragments
      end

    # Rather than using numeric offsets, why not pass in the urn and location,
    # building a URN with a subreference to the token(s) to which the element
    # is applied?
    {text_elements, _final_offset} = fragments |> Enum.reduce({[], 0}, &tag_elements/2)

    {location, text, text_elements}
  end

  def flatten_string(fragment, string \\ "") do
    s =
      case fragment do
        {:string, text} ->
          text

        {:bullet_list, list_elements} ->
          Enum.reduce(list_elements, "", &flatten_string/2)

        {:link, fragments, _url} ->
          Enum.reduce(fragments, "", &flatten_string/2)

        {:list_element, fragments} ->
          Enum.reduce(fragments, "", &flatten_string/2)

        {:note, _} ->
          nil

        {:comment, _} ->
          nil

        {:change, change} ->
          classes = change |> Map.get(:attributes) |> Map.get(:classes)

          if Enum.member?(classes, "insertion") do
            Enum.reduce(change, "", &flatten_string/2)
          end

        {:image, _} ->
          nil

        {:span, _} ->
          nil

        {_k, v} when not is_binary(v) ->
          Enum.reduce(v, "", &flatten_string/2)

        _ ->
          nil
      end

    "#{string}#{s}"
  end

  def tag_elements([string: text], {elements, offset}) do
    {elements, offset + String.length(text)}
  end

  def tag_elements({:string, text}, {elements, offset}) do
    {elements, offset + String.length(text)}
  end

  def tag_elements({:comment, comment}, {elements, offset}) do
    content =
      Map.get(comment, :content, [])
      |> Enum.reduce("", &flatten_string/2)

    attributes = get_comment_attributes(comment, content)

    {elements ++
       [
         %{
           attributes: attributes,
           content:
             content
             |> String.replace(@attribution_regex, "")
             |> String.trim_leading(),
           end_offset: offset,
           start_offset: offset,
           type: :comment
         }
       ], offset}
  end

  def tag_elements({:emph, emph}, {elements, offset}) do
    s = emph |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    # token = String.slice(s, offset..end_offset)

    # THIS COULD HAVE ALL BEEN SO MUCH SIMPLER?
    IO.puts("token: #{s}")

    {elements ++
       [
         %{
           content: s,
           end_offset: end_offset,
           start_offset: offset,
           type: :emph
         }
       ], end_offset}
  end

  def tag_elements({:image, image}, {elements, offset}) do
    s = image |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    {elements ++
       [
         Map.merge(image, %{
           end_offset: end_offset,
           start_offset: offset,
           type: :image
         })
       ], end_offset}
  end

  def tag_elements({:link, link, url}, {elements, offset}) do
    s = link |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    token = String.slice(s, offset..end_offset)

    IO.puts("token: #{token}")

    {elements ++
       [
         %{
           content: url,
           end_offset: end_offset,
           start_offset: offset,
           type: :link
         }
       ], end_offset}
  end

  def tag_elements({:list_element, content}, {elements, offset}) do
    s = content |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    {elements ++
       [
         %{
           content: s,
           end_offset: end_offset,
           start_offset: offset,
           type: :list_element
         }
       ], end_offset}
  end

  def tag_elements({:note, note}, {elements, offset}) do
    {elements ++
       [
         %{
           content: note |> Enum.reduce("", &flatten_string/2),
           start_offset: offset,
           type: :note
         }
       ], offset}
  end

  def tag_elements({:strong, strong}, {elements, offset}) do
    s = strong |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    token = String.slice(s, offset..end_offset)

    IO.puts("token: #{token}")

    {elements ++
       [
         %{
           content: s,
           end_offset: end_offset,
           start_offset: offset,
           type: :strong
         }
       ], end_offset}
  end

  def tag_elements({:superscript, superscript}, {elements, offset}) do
    s = superscript |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    token = String.slice(s, offset..end_offset)

    IO.puts("token: #{token}")

    {elements ++
       [
         %{
           content: s,
           end_offset: end_offset,
           start_offset: offset,
           type: :superscript
         }
       ], end_offset}
  end

  def tag_elements({:underline, underline}, {elements, offset}) do
    s = underline |> Enum.reduce("", &flatten_string/2)
    end_offset = offset + String.length(s)

    token = String.slice(s, offset..end_offset)

    IO.puts("token: #{token}")

    {elements ++
       [
         %{
           content: s,
           end_offset: end_offset,
           start_offset: offset,
           type: :underline
         }
       ], end_offset}
  end

  def tag_elements(fragment, {elements, offset}) do
    Logger.info("Unused fragment when parsing document: #{inspect(fragment)}")

    {elements, offset}
  end

  def get_comment_attributes(comment, s) do
    attrs = Map.get(comment, :attributes)

    if match = Regex.run(@attribution_regex, s) do
      date_string = Enum.fetch!(match, 1) |> String.replace(".", "-")
      {:ok, date_time, _} = DateTime.from_iso8601(date_string <> "T00:00:00Z")

      kv_pairs =
        Map.get(attrs, :key_value_pairs, %{})
        |> Map.put("author", "Gregory Nagy")
        |> Map.put("date", date_time)

      Map.put(attrs, :key_value_pairs, kv_pairs)
    else
      attrs
    end
  end

  def collect_attributes(node) do
    node |> Map.get(:attr, %{}) |> Map.take([:classes, :key_value_pairs])
  end

  def collect_fragments(node),
    do: collect_fragments(node, :children)

  def collect_fragments(node, attr) do
    Map.get(node, attr, []) |> Enum.map(&handle_fragment/1) |> List.flatten()
  end

  def handle_fragment(%Panpipe.AST.BulletList{} = fragment) do
    {:bullet_list, collect_fragments(fragment)}
  end

  def handle_fragment(%Panpipe.AST.Emph{} = fragment),
    do: {:emph, collect_fragments(fragment)}

  def handle_fragment(%Panpipe.AST.Image{} = fragment) do
    {:image, %{content: Map.fetch!(fragment, :target), attributes: collect_attributes(fragment)}}
  end

  def handle_fragment(%Panpipe.AST.Link{} = fragment) do
    {:link, collect_fragments(fragment), Map.fetch!(fragment, :target)}
  end

  def handle_fragment(%Panpipe.AST.ListElement{} = fragment) do
    {:list_element, collect_fragments(fragment)}
  end

  def handle_fragment(%Panpipe.AST.Note{} = fragment),
    do: {:note, collect_fragments(fragment)}

  def handle_fragment(%Panpipe.AST.Para{} = fragment) do
    {:paragraph, collect_fragments(fragment)}
  end

  def handle_fragment(%Panpipe.AST.Str{} = fragment),
    do: {:string, Map.get(fragment, :string, "")}

  def handle_fragment(%Panpipe.AST.Space{} = _fragment),
    do: {:string, " "}

  def handle_fragment(%Panpipe.AST.Span{} = fragment) do
    attributes = collect_attributes(fragment)
    classes = Map.get(attributes, :classes, [])

    fragment_type =
      cond do
        Enum.member?(classes, "deletion") -> :change
        Enum.member?(classes, "insertion") -> :change
        Enum.member?(classes, "paragraph-deletion") -> :change
        Enum.member?(classes, "paragraph-insertion") -> :change
        Enum.member?(classes, "comment-end") -> :comment
        Enum.member?(classes, "comment-start") -> :comment
        true -> :span
      end

    {fragment_type,
     %{
       attributes: attributes,
       content: collect_fragments(fragment)
     }}
  end

  def handle_fragment(%Panpipe.AST.Strong{} = fragment),
    do: {:strong, collect_fragments(fragment)}

  def handle_fragment(%Panpipe.AST.Underline{} = fragment),
    do: {:underline, collect_fragments(fragment)}

  def handle_fragment(fragment) do
    name =
      fragment.__struct__
      |> Module.split()
      |> List.last()
      |> String.downcase()
      |> String.to_atom()

    {name, collect_fragments(fragment)}
  end
end
