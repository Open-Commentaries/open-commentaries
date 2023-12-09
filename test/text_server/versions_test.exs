defmodule TextServer.VersionsTest do
  use TextServer.DataCase

  alias TextServer.Versions
  alias TextServer.Versions.Version

  import TextServer.VersionsFixtures

  @valid_attrs %{
    description: "some description",
    filemd5hash: :crypto.hash(:md5, "some md5") |> Base.encode16(case: :lower),
    filename: "some_filename.docx",
    label: "some label",
    parsed_at: DateTime.utc_now(),
    source: "some source",
    source_link: "https://some.source.link",
    urn: "urn:cts:some:urn",
    version_type: "commentary"
  }

  @invalid_attrs %{
    description: nil,
    filemd5hash: nil,
    filename: nil,
    label: nil,
    parsed_at: nil,
    source: nil,
    source_link: nil,
    urn: nil,
    version_type: nil
  }

  describe "versions" do
    test "list_versions/0 returns a paginated list of versions" do
      version = version_fixture()
      versions = Versions.list_versions().entries

      assert List.first(versions).id == version.id
    end

    test "get_version!/1 returns the version with given id" do
      version = version_fixture()
      assert Versions.get_version!(version.id).label == version.label
    end

    test "create_version/1 with valid data creates a version" do
      language = TextServer.LanguagesFixtures.language_fixture()
      work = TextServer.WorksFixtures.work_fixture()

      attrs =
        @valid_attrs
        |> Enum.into(%{
          language_id: language.id,
          work_id: work.id
        })

      assert {:ok, %Version{} = version} = Versions.create_version(attrs)

      assert version.description == "some description"
      assert version.filemd5hash == :crypto.hash(:md5, "some md5") |> Base.encode16(case: :lower)
      assert version.filename == "some_filename.docx"
      assert version.label == "some label"

      assert DateTime.diff(
               DateTime.utc_now(),
               DateTime.from_naive!(version.parsed_at, "Etc/UTC"),
               :minute
             ) <= 1

      assert version.source == "some source"
      assert version.source_link == "https://some.source.link"
      assert CTS.URN.to_string(version.urn) == "urn:cts:some:urn"
      assert version.version_type == :commentary
    end

    test "create_version/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Versions.create_version(@invalid_attrs)
    end

    test "update_version/2 with valid data updates the version" do
      version = version_fixture()

      update_attrs = %{
        description: "some updated description",
        label: "some updated label",
        urn: "urn:cts:some:updated_urn"
      }

      assert {:ok, %Version{} = version} = Versions.update_version(version, update_attrs)
      assert version.description == "some updated description"
      assert version.label == "some updated label"
      assert CTS.URN.to_string(version.urn) == "urn:cts:some:updated_urn"
    end

    test "update_version/2 with invalid data returns error changeset" do
      version = version_fixture()
      assert {:error, %Ecto.Changeset{}} = Versions.update_version(version, @invalid_attrs)
      assert version.description == Versions.get_version!(version.id).description
    end

    test "delete_version/1 deletes the version" do
      version = version_fixture()
      assert {:ok, %Version{}} = Versions.delete_version(version)
      assert_raise Ecto.NoResultsError, fn -> Versions.get_version!(version.id) end
    end

    test "change_version/1 returns a version changeset" do
      version = version_fixture()
      assert %Ecto.Changeset{} = Versions.change_version(version)
    end

    test "get_table_of_contents/1 returns the table of contents for the given version" do
      version = version_fixture()

      for i <- 1..5 do
        TextServer.TextNodesFixtures.version_text_node_fixture(version, %{
          location: [i, 1, 1]
        })
      end

      toc = Versions.get_table_of_contents(version.id)

      assert Map.get(toc, 1) == %{1 => [1]}
      assert Map.get(toc, 2) == %{1 => [1]}
      assert Map.get(toc, 3) == %{1 => [1]}
      assert Map.get(toc, 4) == %{1 => [1]}
      assert Map.get(toc, 5) == %{1 => [1]}
    end

    test "get_passage_by_urn/1 returns the first page of TextNodes if no passage is given" do
      version = version_fixture()

      for i <- 1..5 do
        for j <- 1..5 do
          TextServer.TextNodesFixtures.version_text_node_fixture(version, %{
            location: [1, i, j]
          })
        end
      end

      {:ok, passage} = Versions.get_passage_by_urn(version.urn)

      assert Enum.count(passage) == 5
      assert List.first(passage).location == [1, 1, 1]
      assert List.last(passage).location == [1, 1, 5]
    end

    test "get_passage_by_urn/1 returns the appropriate page with a passage" do
      version = version_fixture()

      for i <- 1..5 do
        for j <- 1..5 do
          TextServer.TextNodesFixtures.version_text_node_fixture(version, %{
            location: [1, i, j]
          })
        end
      end

      {:ok, passage} = Versions.get_passage_by_urn("#{version.urn}:1.2.1")

      assert Enum.count(passage) == 5
      assert List.first(passage).location == [1, 2, 1]
      assert List.last(passage).location == [1, 2, 5]

      {:ok, passage} = Versions.get_passage_by_urn("#{version.urn}:1.3.1")

      assert Enum.count(passage) == 5
      assert List.first(passage).location == [1, 3, 1]
      assert List.last(passage).location == [1, 3, 5]
    end

    test "get_passage_by_urn/1 returns the appropriate TextNodes with a start and end passage" do
      version = version_fixture()

      for i <- 1..5 do
        for j <- 1..5 do
          TextServer.TextNodesFixtures.version_text_node_fixture(version, %{
            location: [1, i, j]
          })
        end
      end

      {:ok, passage} = Versions.get_passage_by_urn("#{version.urn}:1.2.2-1.2.4")

      assert Enum.count(passage) == 3
      assert List.first(passage).location == [1, 2, 2]
      assert List.last(passage).location == [1, 2, 4]
    end
  end
end
