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

  Each `TextContainer` has an ordered list of block-level `TextNode`s. These
  are what are actually rendered on the page.
  """

  @location_regex ~r/\{\d+\.\d+\.\d+\}/

  defmodule TextContainer do
    defstruct [:location, :urn, :offset]
  end

  defmodule TextBlock do
    defstruct [:type, :text_container_ref, :offset]
  end

  defmodule TextNode do
    defstruct [:type, :text_block_ref, :raw_contents, :offset]
  end

  defmodule TextToken do
    defstruct [:text_node_ref, :content, :offset]
  end

  defmodule TextDecoration do
    defstruct [:type, :text_token_range_ref]
  end

  defmodule CommentStart do
    defstruct [:text_token_ref, :comment_id, :content]
  end

  defmodule CommentEnd do
    defstruct [:text_token_ref, :comment_id]
  end

  @doc """
  Using the `from: {:docx, [:styles]}` option lets us
  maintain custom user-defined styles under the "custom-style"
  key in `node.attr.key_value_pairs`.

  We transform the AST by prepending H2 nodes to
  every location string that we encounter and wrapping
  ever Str node in a Span with its citation fragment
  (based on the current location, which we clumsily
  store in `Process`).
  """
  def parse_and_chunk(%{
        "file" => filename,
        "urn" => urn
      }) do
    {:ok, ast} =
      Panpipe.ast(
        input: filename,
        from: {:docx, [:styles]},
        extract_media: Path.dirname(filename) <> "/media/" <> urn,
        track_changes: "all"
      )

    ast
    |> Panpipe.transform(&add_location_markers/1)
    |> Map.get(:children)
    |> Enum.reduce([[]], fn node, acc ->
      [curr | rest] = acc

      case node do
        %Panpipe.AST.Div{children: children} ->
          [h | rest_children] = children

          # If there is a new location node, reverse the current chunk
          # (so that the nodes are in the right order) and
          # start a new chunk with the current node, removing the header.
          if match?(%Panpipe.AST.Header{attr: %Panpipe.AST.Attr{identifier: _location}}, h) do
            acc = [Enum.reverse(curr) | rest]
            location = h |> Map.get(:attr) |> Map.get(:identifier)

            new_node = %Panpipe.AST.Div{
              node
              | children: rest_children,
                attr: %Panpipe.AST.Attr{node.attr | identifier: location}
            }

            [[new_node] | acc]
          else
            # Otherwise, prepend the current node to the current chunk.
            [[node | curr] | rest]
          end

        _ ->
          # Otherwise, prepend the current node to the current chunk.
          [[node | curr] | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == []))
  end

  def add_location_markers(%Panpipe.AST.Para{children: children} = n) do
    [h | rest] = children

    case h do
      %Panpipe.AST.Str{string: string} ->
        matches = Regex.run(@location_regex, string)

        unless is_nil(matches) do
          location =
            List.first(matches)
            |> String.replace("{", "")
            |> String.replace("}", "")

          Process.put(:current_location, location)

          [
            location_block(string),
            %{n | children: rest}
          ]
        end

      _ ->
        nil
    end
  end

  def add_location_markers(_n), do: nil

  defp location_block(string) do
    location = Process.get(:current_location, ["front-matter"])

    %Panpipe.AST.Header{
      attr: %Panpipe.AST.Attr{identifier: location},
      children: [%Panpipe.AST.Str{string: string}],
      level: 2
    }
  end
end
