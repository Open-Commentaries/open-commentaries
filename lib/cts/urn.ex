# With inspiration from https://github.com/elixir-lang/elixir/blob/v1.12.3/lib/elixir/lib/uri.ex
defmodule CTS.URN do
  @moduledoc """
  Utilities for working with CTS URNs.

  This module provides functions for parsing strings into
  URN structs --- for use in application logic ---
  and for converting URN structs to strings (for storing
  in the database).

  See https://cite-architecture.github.io/ctsurn_spec/ for
  an overview of the CTS URN specification.

  ## Understanding the Struct

  ### Prefix and Protocol

  By definition, the prefix _must_ be `"urn"`, and the protocol
  must be `"cts"`.

  ### The Work and Passage Components

  The `work_component` is a list of the `text_group`, `work,` `version`,
  and `exemplar` strings. It is mainly provide for convenience. When
  stringified, its elements are `.`-separated.

  Similarly, the `passage_component` is a list of `citable_node` and
  (optional) `subsection` tuples, or a pair of the same.

  Examples:

  ```
  urn:cts:greekLit:tlg0525.tlg001.aprip-en
  ```

  References _A Pausanias Reader in Progress_ as a work. Its `work_component`
  is `"tlg0525.tlg001.aprip"`, with `text_group` `"tlg0525"`,
  `work` `"tlg001"`, and `version` `"aprip-en"`.

  If we then append a passage identifier:

  ```
  urn:cts:greekLit:tlg0525.tlg001.aprip-en:1.1.1
  ```

  We are referring to Book 1, Chapter 1, Section 1 of the same work. Its
  `passage_component` is `"1.1.1"`, with `citations` `["1.1.1"]`.

  We can reference a range of passages like so:

  ```
  urn:cts:greekLit:tlg0525.tlg001.aprip-en:1.1.1-1.1.5
  ```

  The `passage_component` is now `"1.1.1-1.1.5"`, and its `citations` are `["1.1.1", "1.1.5"]`.

  If we then add subsection citations to each of the passages:

  ```
  urn:cts:greekLit:tlg0525.tlg001.aprip-en:1.1.1@Greek-1.1.5@Twenty
  ```

  we have a `passage_component` string of `"1.1.1@Greek-1.1.5@Twenty"`,
  `citations` of `{"1.1.1", "1.1.5"}`, and
  `subsections` of `{"Greek", "Twenty"}`.

  We can also add indexes to subsections, indicating the nth occurrence
  of the token:

  ```
  urn:cts:greekLit:tlg0525.tlg001.aprip-en:1.1.1@headland[2]
  ```

  refers to the second appearance of the token "headland" in Book 1, Chapter 1, Section 1.

  @reserved_characters '%/?#:.@-[]'
  @excluded_characters '\\"&<>^`|{}~'
  """

  defstruct prefix: "urn",
            protocol: "cts",
            namespace: nil,
            work_component: nil,
            text_group: nil,
            work: nil,
            version: nil,
            exemplar: nil,
            passage_component: nil,
            citations: nil,
            subsections: nil,
            indexes: nil

  @type t :: %__MODULE__{
          prefix: binary,
          protocol: binary,
          namespace: nil | binary,
          work_component: nil | binary,
          text_group: nil | binary,
          work: nil | binary,
          version: nil | binary,
          exemplar: nil | binary,
          passage_component: nil | binary,
          citations: nil | {binary, nil | binary},
          subsections: nil | {binary, nil | binary},
          indexes: nil | {integer(), nil | integer()}
        }

  @spec parse(binary | CTS.URN.t()) :: CTS.URN.t()
  def parse(%CTS.URN{} = urn), do: urn

  def parse(string) when is_binary(string) do
    components = String.split(string, ":")

    destructure [
                  prefix,
                  protocol,
                  namespace,
                  work_component,
                  passage_component
                ],
                components

    {:ok, work_parts} = parse_work(work_component)

    destructure [
                  text_group,
                  work,
                  version,
                  exemplar
                ],
                work_parts

    {:ok, {passage_start, passage_end}} = parse_passage(passage_component)

    {:ok, {citation_start, subsection_start, subsection_start_index}} =
      parse_citation(passage_start)

    {:ok, {citation_end, subsection_end, subsection_end_index}} = parse_citation(passage_end)

    %CTS.URN{
      prefix: prefix,
      protocol: protocol,
      namespace: namespace,
      work_component: work_component,
      text_group: text_group,
      work: work,
      version: version,
      exemplar: exemplar,
      passage_component: passage_component,
      citations: [citation_start, citation_end],
      subsections: [subsection_start, subsection_end],
      indexes: [subsection_start_index, subsection_end_index]
    }
  end

  def version_urn(%CTS.URN{} = urn) do
    parse(
      "#{urn.prefix}:#{urn.protocol}:#{urn.namespace}:#{urn.text_group}.#{urn.work}.#{urn.version}"
    )
  end

  def version_urn(urn) when is_binary(urn) do
    version_urn(parse(urn))
  end

  def work_urn(%CTS.URN{} = urn) do
    parse("#{urn.prefix}:#{urn.protocol}:#{urn.namespace}:#{urn.text_group}.#{urn.work}")
  end

  def work_urn(urn) when is_binary(urn) do
    work_urn(parse(urn))
  end

  defp parse_work(nil), do: {:ok, nil}

  defp parse_work(string) when is_binary(string), do: {:ok, String.split(string, ".")}

  defp parse_work(other), do: {:ok, other}

  defp parse_passage(nil), do: {:ok, {nil, nil}}

  defp parse_passage(string) do
    citation_parts = String.split(string, "-")

    destructure([passage_start, passage_end], citation_parts)

    {:ok, {passage_start, passage_end}}
  end

  defp parse_citation(nil), do: {:ok, {nil, nil, nil}}

  defp parse_citation(string) do
    citation_parts = String.split(string, "@")

    destructure([citation, subsection], citation_parts)

    {:ok, {token, index}} = parse_subsection(subsection)

    {:ok, {citation, token, index}}
  end

  defp parse_subsection(nil), do: {:ok, {nil, nil}}

  defp parse_subsection(string) do
    regex = ~r/(\w+)(?:\[(\d+)\])?/iu
    subsection_parts = Regex.run(regex, string)
    destructure([_full, token, index], subsection_parts)

    {:ok, {token, index}}
  end

  @spec to_string(binary | CTS.URN.t()) :: binary
  def to_string(urn) when is_binary(urn), do: urn

  def to_string(%CTS.URN{} = urn) do
    s = "#{urn.prefix}:#{urn.protocol}:#{urn.namespace}"

    cond do
      is_nil(urn.work_component) -> s
      is_nil(urn.passage_component) -> s <> ":#{urn.work_component}"
      :else -> s <> ":#{urn.work_component}:#{urn.passage_component}"
    end
  end
end

defimpl Phoenix.HTML.Safe, for: CTS.URN do
  def to_iodata(data), do: CTS.URN.to_string(data)
end

defimpl String.Chars, for: CTS.URN do
  def to_string(s), do: CTS.URN.to_string(s)
end
