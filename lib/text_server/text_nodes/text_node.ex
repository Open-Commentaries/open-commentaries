defmodule TextServer.TextNodes.TextNode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "text_nodes" do
    # FIXME: (charles) Eventually, location will need to
    # be an array of strings, not integers. Consider citations for
    # Plato, Aristotle, etc.
    field :location, {:array, :integer}
    field :node_type, Ecto.Enum, values: [:bullet_list, :div, :para]
    field :normalized_text, :string
    field :text, :string
    field :urn, TextServer.Ecto.Types.CTS_URN
    field :_search, TextServer.Ecto.Types.TsVector

    field :graphemes_with_tags, :any, virtual: true

    belongs_to :text_container, TextServer.TextContainers.TextContainer
    belongs_to :version, TextServer.Versions.Version

    has_many :text_elements, TextServer.TextElements.TextElement,
      foreign_key: :start_text_node_id,
      preload_order: [asc: :start_offset]

    has_many :text_tokens, TextServer.TextTokens.TextToken

    timestamps()
  end

  @doc false
  def changeset(text_node, attrs) do
    text_node
    |> cast(attrs, [:version_id, :location, :text, :urn, :text_container_id])
    |> validate_required([:location, :text, :urn])
    |> assoc_constraint(:version)
    |> assoc_constraint(:text_container)
    |> unique_constraint([:version_id, :location, :urn])
  end

  @search_types %{location: {:array, :any}, search_string: :string, urn: :string}

  def search_changeset(attrs \\ %{}) do
    cast({%{}, @search_types}, attrs, [:location, :search_string, :urn])
    |> validate_required([:search_string])
    |> update_change(:search_string, &String.trim/1)
    |> validate_length(:search_string, min: 2)
  end

  defmodule Tag do
    @enforce_keys [:name]

    defstruct [:name, :metadata]
  end

  def tag_graphemes(text_node) do
    elements =
      text_node.text_elements |> Enum.filter(fn e -> e.element_type.name != "comment" end)

    comments =
      text_node.text_elements |> Enum.filter(fn e -> e.element_type.name == "comment" end)

    text = text_node.text

    # turn the bare graphemes list into an indexed list of tuples
    # representing the grapheme and associated inline metadata
    # Sort of akin to what ProseMirror does: https://prosemirror.net/docs/guide/#doc
    graphemes =
      String.graphemes(text)
      |> Enum.with_index(fn g, i -> {i, g, []} end)

    tagged_graphemes = apply_tags(elements, graphemes)
    commented_graphemes = apply_comments(comments, tagged_graphemes)

    grouped_graphemes =
      commented_graphemes
      |> Enum.reduce([], fn tagged_grapheme, acc ->
        {_i, g, tags} = tagged_grapheme
        first = List.first(acc)

        if first == nil do
          [{[g], tags}]
        else
          {g_list, first_tags} = first

          if first_tags == tags do
            List.replace_at(acc, 0, {g_list ++ [g], tags})
          else
            [{[g], tags} | acc]
          end
        end
      end)
      |> Enum.reverse()

    %{text_node | graphemes_with_tags: grouped_graphemes}
  end

  defp apply_tags(elements, graphemes) do
    Enum.reduce(elements, graphemes, fn el, gs ->
      tagged =
        gs
        |> Enum.map(fn g ->
          {i, g, tags} = g

          cond do
            el.element_type.name == "image" && i == el.start_offset - 1 ->
              {i, g,
               tags ++ [%Tag{name: el.element_type.name, metadata: %{src: el.content, id: el.id}}]}

            el.element_type.name == "note" && i == el.start_offset - 1 ->
              {i, g,
               tags ++
                 [%Tag{name: el.element_type.name, metadata: %{content: el.content, id: el.id}}]}

            i >= el.start_offset && i < el.end_offset ->
              {i, g,
               tags ++
                 [
                   %Tag{
                     name: el.element_type.name,
                     metadata: %{src: Map.get(el, :content), id: el.id}
                   }
                 ]}

            true ->
              {i, g, tags}
          end
        end)

      tagged
    end)
  end

  defp apply_comments(comments, graphemes) do
    ranged_comments =
      comments
      |> Enum.group_by(
        &comment_id/1,
        fn c ->
          author = comment_author(c)
          date = comment_date(c)

          Map.new(
            id: Integer.to_string(c.id),
            author: author,
            content: c.content,
            date: date,
            offset: c.start_offset
          )
        end
      )
      |> Enum.map(fn {_id, start_and_end} ->
        [h | t] = start_and_end

        range =
          unless t == [] do
            t = hd(t)
            h.offset..(t.offset - 1)
          else
            h.offset..Enum.count(graphemes)
          end

        Map.put(h, :range, range)
      end)

    graphemes
    |> Enum.map(fn g ->
      {i, g, tags} = g

      applicable_comments =
        ranged_comments
        |> Enum.filter(fn c -> i in c.range end)
        |> Enum.map(fn c -> %Tag{name: "comment", metadata: c} end)

      {i, g, tags ++ applicable_comments}
    end)
  end

  defp comment_kv_pairs(comment), do: Map.get(comment.attributes, "key_value_pairs", %{})
  defp comment_author(comment), do: comment_kv_pairs(comment) |> Map.get("author")

  defp comment_date(comment) do
    try do
      {:ok, date, _} = comment_kv_pairs(comment) |> Map.get("date") |> DateTime.from_iso8601()
      date
    rescue
      _ -> nil
    end
  end

  defp comment_id(comment), do: comment_kv_pairs(comment) |> Map.get("id")
end
