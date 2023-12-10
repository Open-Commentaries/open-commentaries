defmodule TextServer.Ingestion.Docx do
  @moduledoc """
  During the ingestion process, we need to parse location
  identifiers given by the `@location_regex` into ordered
  `TextContainer`s.

  Each `TextContainer` can have any number of block-level
  text nodes. Block-level nodes are defined by
  [Pandoc](https://hackage.haskell.org/package/pandoc-types-1.23.1/docs/Text-Pandoc-Definition.html#t:Block),
  which correspond directly to Panpipe.AST structs:

  - Plain
  - Para
  - LineBlock
  - CodeBlock
  - RawBlock
  - BlockQuote
  - OrderedList
  - BulletList
  - DefinitionList
  - Header
  - HorizontalRule
  - Table
  - Figure
  - Div

  Each of these block-level nodes can have special rules for
  its children, and only some of them can contain attributes (like
  their citable location). Hence the need for an additional
  layer of indirection.

  Each `TextContainer` has an ordered list of block-level nodes. These
  are what are actually rendered on the page.
  """

  @location_regex ~r/\{\d+\.\d+\.\d+\}/

  # the @attribution_regex is a special case for matching
  # old comments by Greg Nagy ("GN") that have been
  # manually attributed. Normally, attribution will come
  # directly from a comment's XML.
  @attribution_regex ~r/\[\[GN\s(\d{4}\.\d{2}\.\d{2})\]\]/

  defmodule TextContainer do
    defstruct [:location, :content]
  end

  @doc """
  Using the `from: {:docx, [:styles]}` option lets us
  maintain custom user-defined styles under the "custom-style"
  key in `node.attr.key_value_pairs`.
  """
  def parse(%{
        "file" => filename,
        "name" => _name,
        "urn" => urn,
        "references" => _references
      }) do
    {:ok, ast} =
      Panpipe.ast(
        input: filename,
        from: {:docx, [:styles]},
        extract_media: Path.dirname(filename) <> "/media/" <> urn,
        track_changes: "accept"
      )

    Process.put(:current_document_location, [0])

    ast
    |> Panpipe.transform(&mark_location/1)
    |> Enum.filter(fn node ->
      match?(%Panpipe.AST.Div{}, node)
    end)
    |> Enum.map(&Map.delete(&1, :parent))
    |> Enum.chunk_by(fn node ->
      Map.get(node, :attr) |> Map.get(:identifier)
    end)
  end

  def mark_location(%Panpipe.AST.Para{children: children} = n) do
    [h | _rest] = children

    case h do
      %Panpipe.AST.Str{string: string} ->
        matches = Regex.run(@location_regex, string)

        if !is_nil(matches) do
          location =
            List.first(matches)
            |> String.replace("{", "")
            |> String.replace("}", "")

          Process.put(:current_document_location, location)
        end

      _ ->
        nil
    end

    wrap_children_in_div(children, n.__struct__)
  end

  def mark_location(n) do
    if Panpipe.AST.Node.block?(n) do
      wrap_children_in_div(n.children, n.__struct__)
    end
  end

  @doc """
  Keeping the `parent_type` is not terrible for getting the `location`
  identifiers attached to each node.
  """
  def wrap_children_in_div(children, parent_type) do
    div = %Panpipe.AST.Div{children: children}
    location = Process.get(:current_document_location)

    %{
      div
      | attr: %Panpipe.AST.Attr{
          identifier: location,
          key_value_pairs: %{"location" => location, "block_type" => parent_type}
        }
    }
  end
end
