defmodule TextServer.Ingestion.NamedEntities do
  alias TextServer.ElementTypes
  alias TextServer.TextElements
  alias TextServer.TextNodes

  def ingest_jsonl(path) do
    {:ok, element_type} = ElementTypes.find_or_create_element_type(%{name: "named_entity"})

    File.stream!(path)
    |> Stream.each(fn line ->
      Jason.decode!(line)
      |> Enum.filter(&(Map.get(&1, "score") > 0.7))
      |> Enum.each(fn entity ->
        urn =
          Map.get(entity, "text_node_urn")

        text_node = TextNodes.get_by(%{urn: urn})

        TextElements.find_or_create_text_element(%{
          attributes: Map.get(entity, "attributes"),
          content: Map.get(entity, "content"),
          element_type_id: element_type.id,
          end_offset: Map.get(entity, "end_offset"),
          end_text_node_id: text_node.id,
          start_offset: Map.get(entity, "start_offset"),
          start_text_node_id: text_node.id
        })
      end)
    end)
    |> Stream.run()
  end
end
