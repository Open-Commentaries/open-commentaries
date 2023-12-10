defmodule TextServer.Ingestion.Process do
  def run do
    {:ok, config} = TextServer.Ingestion.Config.parse()

    commentaries = Map.get(config, "commentaries", [])
    editions = Map.get(config, "editions", [])
    translations = Map.get(config, "translations", [])

    editions
    |> Enum.each(fn edition ->
      file = Map.get(edition, "file")

      _parsed =
        case Path.extname(file) do
          ".docx" -> TextServer.Ingestion.Docx.parse(edition, "edition")
          ".xml" -> "NOT YET IMPLEMENTED"
          _ -> "NOT SUPPORTED"
        end
    end)

    commentaries
    |> Enum.each(fn commentary ->
      file = Map.get(commentary, "file")

      _parsed =
        case Path.extname(file) do
          ".docx" -> TextServer.Ingestion.Docx.parse(commentary, "commentary")
          ".xml" -> "NOT YET IMPLEMENTED"
          _ -> "NOT SUPPORTED"
        end
    end)

    translations
    |> Enum.each(fn translation ->
      file = Map.get(translation, "file")

      _parsed =
        case Path.extname(file) do
          ".docx" -> TextServer.Ingestion.Docx.parse(translation, "translation")
          ".xml" -> "NOT YET IMPLEMENTED"
          _ -> "NOT SUPPORTED"
        end
    end)
  end
end
