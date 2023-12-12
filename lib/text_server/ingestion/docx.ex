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

  # the @attribution_regex is a special case for matching
  # old comments by Greg Nagy ("GN") that have been
  # manually attributed. Normally, attribution will come
  # directly from a comment's XML.
  @attribution_regex ~r/\[\[GN\s(\d{4}\.\d{2}\.\d{2})\]\]/

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
          first = List.first(children)

          # If there is a new location node, reverse the current chunk
          # (so that the nodes are in the right order) and
          # start a new chunk with the current node.
          if match?(%Panpipe.AST.Header{attr: %Panpipe.AST.Attr{identifier: _location}}, first) do
            acc = [Enum.reverse(curr) | rest]

            [[node] | acc]
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
  end

  def add_location_markers(%Panpipe.AST.Para{children: children} = n) do
    [h | rest] = children

    case h do
      %Panpipe.AST.Str{string: string} ->
        matches = Regex.run(@location_regex, string)

        if !is_nil(matches) do
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

  def add_location_markers(%Panpipe.AST.Str{string: " "}), do: nil

  def add_location_markers(%Panpipe.AST.Str{string: string} = n) do
    location = Process.get(:current_location)

    unless is_nil(location) do
      citation_key = "#{location}:#{string}"

      # Somewhat confusingly, the :halt tuple does not halt
      # the transformation, but rather prevents it from recursing
      # into the :children field, which is the Str node that it
      # has just seen.
      {:halt,
       %Panpipe.AST.Span{
         attr: %Panpipe.AST.Attr{key_value_pairs: %{"citation" => citation_key}},
         children: [n]
       }}
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
