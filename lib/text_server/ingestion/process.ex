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
      # |> Enum.with_index()
      # |> Enum.map(fn {chunk, offset} ->
      #   IO.inspect(chunk)

      #   # location = Map.get(chunk, :attr) |> Map.get(:identifier)

      #   # if location == "" do
      #   #   IO.inspect(chunk)
      #   # end

      #   # {:ok, container} =
      #   #   TextContainers.find_or_create_text_container(%{
      #   #     location: location |> Enum.map(&to_string(&1)),
      #   #     offset: offset,
      #   #     version_id: version.id,
      #   #     urn: urn <> ":" <> Enum.join(location, ".")
      #   #   })

      #   # create_text_nodes(container, chunk)
      # end)
    end)
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
      |> IO.inspect()

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
