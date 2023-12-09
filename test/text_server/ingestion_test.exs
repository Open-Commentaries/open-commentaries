defmodule TextServer.IngestionTest do
  use TextServer.DataCase

  alias TextServer.Ingestion
  alias TextServer.TextNodes
  alias TextServer.Versions.Version

  import TextServer.VersionsFixtures

  describe "Version DOCX parsing" do
    import TextServer.VersionsFixtures

    test "parse_version/1 can parse a docx" do
      version = version_with_docx_fixture()

      assert {:ok, %Version{} = _} = Ingestion.Version.parse_version(version)

      text_node = TextNodes.get_by(%{version_id: version.id, location: [1, 1, 1]})

      assert String.contains?(
               text_node.text,
               "This is a test document for TextServer.Versions.parse_xml/1"
             )

      text_node = TextNodes.get_by(%{version_id: version.id, location: [1, 2, 1]})

      assert String.contains?(
               text_node.text,
               "Now we want to test inline styles and TextElements."
             )
    end
  end
end
