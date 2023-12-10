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

  alias TextServer.TextContainers
  alias TextServer.TextElements
  alias TextServer.TextNodes
  alias TextServer.Versions
  alias TextServer.Works

  @doc """
  Using the `from: {:docx, [:styles]}` option lets us
  maintain custom user-defined styles under the "custom-style"
  key in `node.attr.key_value_pairs`.

  The `Panpipe.AST.Div` objects that are returned by parse/1
  are efectively `TextContainer`s. Each container holds
  the location of all of its child nodes.

  We need to figure out how to store the child nodes
  so that they can be re-assembled into HTML
  with the correct format and so that we can attach
  other elements (named entity tags etc.) to them.
  """
  def parse(
        %{
          "file" => filename,
          "name" => name,
          "urn" => urn
        },
        version_type
      ) do
    {:ok, ast} =
      Panpipe.ast(
        input: filename,
        from: {:docx, [:styles]},
        extract_media: Path.dirname(filename) <> "/media/" <> urn,
        track_changes: "accept"
      )

    Process.put(:current_document_location, ["preface"])

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

    ast
    |> Panpipe.transform(&mark_location/1)
    |> Enum.filter(fn node ->
      match?(%Panpipe.AST.Div{}, node)
    end)
    |> Enum.map(&Map.delete(&1, :parent))
    |> Enum.chunk_by(fn node ->
      Map.get(node, :attr) |> Map.get(:identifier)
    end)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, offset} ->
      first = List.first(chunk)
      location = Map.get(first, :attr) |> Map.get(:identifier, "preface")

      urn =
        if location == [0] do
          "#{version.urn}:preface"
        else
          "#{version.urn}:#{location}"
        end

      {:ok, container} =
        TextContainers.find_or_create_text_container(%{
          location: location |> Enum.map(&to_string(&1)),
          offset: offset,
          version_id: version.id,
          urn: urn
        })

      chunk
      |> Enum.map(fn text_node_raw ->
        node_type =
          Map.get(text_node_raw, :attr)
          |> Map.get(:key_value_pairs)
          |> Map.get("block_type")
          |> Module.split()
          |> List.last()
          |> Recase.KebabCase.convert()

        text_node_raw
        |> Map.put(:text_container_id, container.id)
        |> Map.put(:node_type, node_type)
        |> IO.inspect()

        # |> TextNodes.find_or_create_text_node()
      end)
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
            |> String.split(".")

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
