defmodule DataSchemas.TextGroup.CTSDocument do
  import DataSchema, only: [data_schema: 1]

  @moduledoc """
  This module provides DataSchema facilities for parsing
  the __cts__.xml file that accompanies a work.
  """

  @data_accessor DataSchemas.XPathAccessor
  data_schema(
    field: {:urn, "/ti:textgroup/@urn", &{:ok, to_string(&1)}},
    field: {:groupname, "/ti:textgroup/ti:groupname/text()", &{:ok, to_string(&1)}}
  )
end
