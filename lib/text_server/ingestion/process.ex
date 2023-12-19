defmodule TextServer.Ingestion.Process do
  alias TextServer.TextContainers
  alias TextServer.TextElements
  alias TextServer.TextNodes
  alias TextServer.Versions
  alias TextServer.Works

  def run do
    {:ok, config} = TextServer.Ingestion.Config.parse()

    # Map.get(config, "editions", [])
    # |> process_versions("edition")

    # Map.get(config, "commentaries", [])
    # |> process_versions("commentary")

    Map.get(config, "translations", [])
    |> process_versions("translation")
  end

  def process_versions(configs, version_type) do
    {:ok, bert} = Bumblebee.load_model({:hf, "dslim/bert-base-NER"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "bert-base-cased"})

    serving = Bumblebee.Text.token_classification(bert, tokenizer, aggregation: :same)

    configs
    |> Enum.map(fn %{"file" => file, "urn" => urn} = config ->
      version = create_version(config, version_type)

      parsed =
        case Path.extname(file) do
          ".docx" -> TextServer.Ingestion.Docx.parse_and_chunk(config)
          ".xml" -> "NOT YET IMPLEMENTED"
          _ -> "NOT SUPPORTED"
        end

      parsed
      |> Enum.with_index()
      |> Enum.map(fn {chunk, offset} ->
        location = chunk |> List.first() |> Map.get(:attr) |> Map.get(:identifier)

        document = %Panpipe.Document{children: chunk}
        plain_text = Panpipe.to_plain(document)
        token_classifications = classify_tokens(serving, plain_text)

        ner_ast =
          document
          |> Panpipe.transform(fn
            %Panpipe.AST.Str{string: string} = n ->
              entity_match =
                token_classifications
                |> Enum.find(fn t ->
                  String.starts_with?(t.phrase, string) or String.starts_with?(string, t.phrase)
                end)

              if entity_match do
                {:halt,
                 %Panpipe.AST.Span{
                   attr: %Panpipe.AST.Attr{
                     key_value_pairs: %{"entity" => Jason.encode!(entity_match)}
                   },
                   children: [n]
                 }}
              end

            _ ->
              nil
          end)

        fragments = TextServer.Ingestion.Version.collect_fragments(ner_ast)

        TextServer.Ingestion.Version.serialize_fragments(
          location |> String.split("."),
          fragments
        )
        |> Enum.map(fn {location, text, elements} ->
          {:ok, text_node} =
            TextNodes.find_or_create_text_node(%{
              version_id: version.id,
              location: location,
              text: text,
              urn: "#{version.urn}:#{location}"
            })

          TextNodes.update_text_node(text_node, %{text: text})

          _elements_and_errors = TextElements.find_or_create_text_elements(text_node, elements)
        end)
      end)
    end)
  end

  def classify_tokens(serving, text) do
    Nx.Serving.run(serving, text)
    |> Map.get(:entities)
    |> Enum.reduce([], fn
      entity, [] ->
        [entity]

      entity, acc ->
        [h | rest] = acc

        phrase = entity |> Map.get(:phrase)

        if String.starts_with?(phrase, "##") do
          h_phrase = h |> Map.get(:phrase)
          joined_phrase = String.replace(phrase, "##", h_phrase)
          new_h = %{h | phrase: joined_phrase, end: entity.end}

          [new_h | rest]
        else
          [entity | acc]
        end
    end)
    |> Enum.reverse()
  end

  def create_text_nodes(container, text_nodes) do
    text_nodes
    |> Enum.map(fn text_node_raw ->
      node_type =
        Map.get(text_node_raw, :attr)
        |> Map.get(:key_value_pairs)
        |> Map.get("block_type")

      text_node_raw
      |> Map.put(:text_container_id, container.id)
      |> Map.put(:node_type, node_type)

      # |> TextNodes.find_or_create_text_node()
    end)
  end

  def create_version(
        %{"urn" => urn, "file" => filename, "name" => name} = _version,
        version_type
      ) do
    work_urn = CTS.URN.work_urn(urn)
    {:ok, work} = Works.get_work_by_urn(work_urn)

    md5 = :crypto.hash(:md5, File.read!(filename)) |> Base.encode16(case: :lower)

    {:ok, version} =
      Versions.find_or_create_version(%{
        filename: filename,
        filemd5hash: md5,
        work_id: work.id,
        label: name,
        urn: urn,
        version_type: version_type
      })

    version
  end
end
