defmodule DataSchemas.Version do
  import DataSchema, only: [data_schema: 1]

  @data_accessor DataSchemas.PostgresXPathAccessor
  data_schema(has_one: {:body, "/tei:TEI/tei:text/tei:body", DataSchemas.Version.Body})
end

# FIXME: (charles) the Body schema should be defined at runtime
# based on the refsDecl

# defmodule DataSchemas.Version.Body do
#   import DataSchema, only: [data_schema: 1]

#   @data_accessor DataSchemas.XPathAccessor
#   data_schema(
#     has_many: {:lines, "//l", DataSchemas.Version.Body.Line},
#     has_many: {:notes, "//note", DataSchemas.Version.Body.Note},
#     has_many: {:speakers, "//sp", DataSchemas.Version.Body.Speaker}
#   )
# end

# defmodule DataSchemas.Version.Body.Line do
#   import DataSchema, only: [data_schema: 1]

#   @data_accessor DataSchemas.XPathAccessor
#   data_schema(
#     field: {:n, "./@n", &{:ok, &1}},
#     field: {:raw, ".", &{:ok, &1}},
#     field: {:text, ".//text()", &{:ok, &1}}
#   )
# end

# defmodule DataSchemas.Version.Body.Note do
#   import DataSchema, only: [data_schema: 1]

#   @data_accessor DataSchemas.XPathAccessor
#   data_schema(
#     field: {:n, "./@n", &{:ok, &1}},
#     field: {:text, "./text()", &{:ok, &1}}
#   )
# end

# defmodule DataSchemas.Version.Body.Speaker do
#   import DataSchema, only: [data_schema: 1]

#   @moduledoc """
#   DataSchema for `speaker`s in TEI XML. Should we
#   unwrap the `has_many` below and instead treat it
#   as an aggregate that collects all of the @n attributes
#   for lines under a given speaker in the XML?
#   """

#   @data_accessor DataSchemas.XPathAccessor
#   data_schema(
#     field: {:name, "./speaker/text()", &{:ok, &1}},
#     list_of: {:lines, "./l/@n", &{:ok, to_string(&1)}}
#   )
# end
