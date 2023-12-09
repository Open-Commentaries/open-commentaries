defmodule TextServer.Versions do
  @moduledoc """
  The Versions context.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Ecto

  alias TextServer.Repo

  alias TextServer.Languages
  alias TextServer.Projects.Version, as: ProjectVersion
  alias TextServer.TextNodes
  alias TextServer.TextNodes.TextNode
  alias TextServer.Versions.Passage
  alias TextServer.Versions.Version
  alias TextServer.Versions.XmlDocuments.XmlDocument
  alias TextServer.Works
  alias TextServer.Works.Work

  defmodule VersionPassage do
    defstruct [:version_id, :passage, :passage_number, :text_nodes, :total_passages]
  end

  def create_commentary(work, version_data) do
    create_version(work, version_data, :commentary)
  end

  def create_edition(work, version_data) do
    create_version(work, version_data, :edition)
  end

  def create_translation(work, version_data) do
    create_version(work, version_data, :translation)
  end

  def create_version(work, version_data, version_type) do
    urn = Map.get(version_data, :urn) |> CTS.URN.parse()
    file = get_version_file(urn)
    xml_raw = File.read!(file)
    md5 = :crypto.hash(:md5, xml_raw) |> Base.encode16(case: :lower)
    language = Languages.get_language_by_iso_code!(version_data.language)

    {:ok, version} =
      Map.take(version_data, [:description, :label])
      |> Map.merge(%{
        filename: file,
        filemd5hash: md5,
        language_id: language.id,
        urn: urn,
        version_type: version_type,
        work_id: work.id
      })
      |> find_or_create_version()

    create_xml_document!(version, %{document: xml_raw})
  end

  @doc """
  Creates a version.

  ## Examples

      iex> create_version(%{field: value})
      {:ok, %Version{}}

      iex> create_version(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_version(attrs \\ %{}) do
    %Version{}
    |> Version.changeset(attrs)
    |> Repo.insert()
  end

  def create_version!(attrs \\ %{}) do
    %Version{}
    |> Version.changeset(attrs)
    |> Repo.insert!()
  end

  def find_or_create_version(attrs \\ %{}) do
    urn = Map.get(attrs, :urn, Map.get(attrs, "urn"))
    query = from(v in Version, where: v.urn == ^urn)

    case Repo.one(query) do
      nil ->
        create_version(attrs)

      version ->
        {:ok, version}
    end
  end

  def upsert_version(attrs) do
    urn = Map.get(attrs, :urn, Map.get(attrs, "urn"))
    query = from(v in Version, where: v.urn == ^urn)

    case Repo.one(query) do
      nil -> create_version(attrs)
      version -> update_version(version, attrs)
    end
  end

  @doc """
  This create_version/2 is for creating a version from a docx file.
  """
  def create_version(attrs, project) do
    urn = make_version_urn(attrs, project)

    {:ok, version} =
      Repo.transaction(fn ->
        {:ok, version} =
          %Version{}
          |> Version.changeset(attrs |> Map.put("urn", urn))
          |> Repo.insert()

        {:ok, _project_version} =
          %ProjectVersion{}
          |> ProjectVersion.changeset(%{version_id: version.id, project_id: project.id})
          |> Repo.insert()

        version
      end)

    %{id: version.id}
    |> TextServer.Workers.VersionWorker.new()
    |> Oban.insert()
  end

  def create_versions_of_work(%Work{} = work) do
    {:ok, work_cts_data} = Works.get_work_cts_data(work)

    Map.get(work_cts_data, :commentaries) |> Enum.each(&create_commentary(work, &1))
    Map.get(work_cts_data, :editions) |> Enum.each(&create_edition(work, &1))
    Map.get(work_cts_data, :translations) |> Enum.each(&create_translation(work, &1))
  end

  def get_version_file(urn) do
    path = CTS.base_cts_dir() <> "/" <> Works.get_work_dir(urn) <> "/#{urn.work_component}.xml"

    if File.exists?(path) do
      path
    else
      :enoent
    end
  end

  @spec list_versions(keyword | map) :: Scrivener.Page.t()
  @doc """
  Returns the list of versions.

  ## Examples

      iex> list_versions()
      [%Version{}, ...]

  """
  def list_versions(params \\ [page: 1, page_size: 20]) do
    Version
    |> Repo.paginate(params)
  end

  @spec list_versions_except(list(integer()), keyword | map) :: Scrivener.Page.t()
  def list_versions_except(version_ids, pagination_params \\ []) do
    Version
    |> where([e], e.id not in ^version_ids)
    |> Repo.paginate(pagination_params)
  end

  def list_sibling_versions(version) do
    Version
    |> where([v], v.work_id == ^version.work_id and v.id != ^version.id)
    |> Repo.all()
  end

  def list_versions_for_urn(%CTS.URN{} = urn, opts \\ []) do
    from(v in Version,
      where:
        fragment("? ->> ? = ?", v.urn, "namespace", ^urn.namespace) and
          fragment("? ->> ? = ?", v.urn, "text_group", ^urn.text_group) and
          fragment("? ->> ? = ?", v.urn, "work", ^urn.work)
    )
    |> Repo.all(opts)
  end

  @doc """
  Gets a single version.

  Raises `Ecto.NoResultsError` if the Version does not exist.

  ## Examples

      iex> get_version!(123)
      %Version{}

      iex> get_version!(456)
      ** (Ecto.NoResultsError)

  """
  def get_version!(id), do: Repo.get!(Version, id) |> Repo.preload(:language)

  def get_version_by_urn!(urn) when is_binary(urn) do
    get_version_by_urn!(CTS.URN.parse(urn))
  end

  def get_version_by_urn!(%CTS.URN{} = urn) do
    version = get_version_by_urn(urn)

    if is_nil(version) do
      raise "No version found for urn #{urn}"
    else
      version
    end
  end

  def get_version_by_urn(%CTS.URN{} = urn) do
    version_urn_s = "#{urn.prefix}:#{urn.protocol}:#{urn.namespace}:#{urn.work_component}"
    Repo.get_by(Version, urn: version_urn_s)
  end

  defp make_version_urn(version_params, project) do
    work_id = Map.fetch!(version_params, "work_id")
    label = Map.fetch!(version_params, "label")
    work = Works.get_work!(work_id)
    "#{work.urn}.#{String.downcase(project.domain)}-#{Recase.to_kebab(label)}-en"
  end

  @doc """
  Updates a version.

  ## Examples

      iex> update_version(version, %{field: new_value})
      {:ok, %Version{}}

      iex> update_version(version, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_version(%Version{} = version, attrs) do
    version
    |> Version.changeset(attrs)
    |> Repo.update()
  end

  def create_passage(attrs) do
    {:ok, passage} =
      %Passage{}
      |> Passage.changeset(attrs)
      |> Repo.insert()

    {:ok, passage}
  end

  def get_passage_by_urn(urn) do
    try do
      version = get_version_by_urn!(urn)
      {:ok, list_version_text_nodes(version, CTS.URN.parse(urn).passage_component)}
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
        {:error, e}
    end
  end

  def list_version_text_nodes(%Version{} = version, passages) when is_nil(passages) do
    cardinality =
      TextNode
      |> where([t], t.version_id == ^version.id)
      |> select(fragment("max(cardinality(location))"))
      |> Repo.one()

    start_location = List.duplicate(1, cardinality)
    TextNodes.list_text_nodes_by_version_from_start_location(version, start_location)
  end

  def list_version_text_nodes(%Version{} = version, passage_s) when is_binary(passage_s) do
    list_version_text_nodes(version, String.split(passage_s, "-"))
  end

  def list_version_text_nodes(%Version{} = version, passages) when length(passages) == 1 do
    start_location = List.first(passages) |> String.split(".") |> Enum.map(&String.to_integer/1)
    TextNodes.list_text_nodes_by_version_from_start_location(version, start_location)
  end

  def list_version_text_nodes(%Version{} = version, passages) when length(passages) == 2 do
    start_location = List.first(passages) |> String.split(".") |> Enum.map(&String.to_integer/1)
    end_location = List.last(passages) |> String.split(".") |> Enum.map(&String.to_integer/1)
    TextNodes.list_text_nodes_by_version_between_locations(version, start_location, end_location)
  end

  def get_version_passage(version_id, passage_number \\ 1) do
    total_passages = get_total_passages(version_id)

    n =
      if passage_number > total_passages do
        total_passages
      else
        passage_number
      end

    passage =
      Passage
      |> where([p], p.version_id == ^version_id and p.passage_number == ^n)
      |> Repo.one()

    if is_nil(passage) do
      version = get_version!(version_id)

      case paginate_version(version.id) do
        {:ok, _} -> get_version_passage(version_id, passage_number)
        {:error, message} -> raise message
      end
    else
      text_nodes =
        TextNodes.list_text_nodes_by_version_between_locations(
          version_id,
          passage.start_location,
          passage.end_location
        )

      %VersionPassage{
        version_id: version_id,
        passage: passage,
        passage_number: passage.passage_number,
        text_nodes: text_nodes,
        total_passages: total_passages
      }
    end
  end

  def get_version_passage_by_location(version_id, location) when is_list(location) do
    case Passage
         |> where(
           [p],
           p.version_id == ^version_id and
             p.start_location <= ^location and
             p.end_location >= ^location
         )
         |> Repo.one() do
      nil ->
        Logger.warning("No text_nodes found.")
        nil

      passage ->
        text_nodes =
          TextNodes.list_text_nodes_by_version_between_locations(
            version_id,
            passage.start_location,
            passage.end_location
          )

        %VersionPassage{
          version_id: version_id,
          passage: passage,
          passage_number: passage.passage_number,
          text_nodes: text_nodes,
          total_passages: get_total_passages(version_id)
        }
    end
  end

  @doc """
  Returns the total number of passages for a given version.

  ## Examples
    iex> get_total_passages(1)
    20
  """

  def get_total_passages(version_id) do
    total_passages_query =
      from(
        p in Passage,
        where: p.version_id == ^version_id,
        select: max(p.passage_number)
      )

    Repo.one(total_passages_query)
  end

  @doc """
  Returns a table of contents represented by a(n unordered) map of maps.

  ## Examples
    iex> get_table_of_contents(1)
    %{7 => %{1 => [1, 2, 3], 4 => [1, 2], 2 => [1, 2, 3], ...}, ...}
  """

  def get_table_of_contents(version_id) do
    locations = TextNodes.list_locations_by_version_id(version_id)

    locations |> Enum.reduce(%{}, &nest_location/2)
  end

  defp nest_location(l, acc) when length(l) == 3 do
    [x | rest] = l
    [y | z] = rest

    curr =
      case acc do
        %{^x => %{^y => value}} -> value
        _ -> []
      end

    put_in(acc, Enum.map([x, y], &Access.key(&1, %{})), curr ++ z)
  end

  defp nest_location(l, acc) when length(l) == 2 do
    [x | y] = l

    Map.update(acc, x, y, fn arr -> arr ++ y end)
  end

  defp nest_location(l, acc) when length(l) == 1 do
    acc
  end

  @doc """
  Groups an Version's TextNodes into Pages by location.
  Returns {:ok, total_passages} on success.
  """

  def paginate_version(version_id) do
    q =
      from(
        t in TextNode,
        where: t.version_id == ^version_id,
        order_by: [asc: t.location]
      )

    text_nodes = Repo.all(q)
    group_and_paginate_text_nodes(version_id, text_nodes)
  end

  defp group_and_paginate_text_nodes(version_id, text_nodes) when length(text_nodes) == 0 do
    {:error, "No text nodes found for version #{version_id}."}
  end

  defp group_and_paginate_text_nodes(version_id, text_nodes) do
    grouped_text_nodes =
      text_nodes
      |> Enum.filter(fn tn -> tn.location != [0] end)
      |> Enum.group_by(fn tn ->
        location = tn.location

        if length(location) > 1 do
          Enum.take(location, length(tn.location) - 1)
        else
          line = List.first(location)

          Integer.floor_div(line, 20)
        end
      end)

    keys = Map.keys(grouped_text_nodes) |> Enum.sort()

    keys
    |> Enum.with_index()
    |> Enum.each(fn {k, i} ->
      text_nodes = Map.get(grouped_text_nodes, k)
      first_node = List.first(text_nodes)
      last_node = List.last(text_nodes)

      create_passage(%{
        end_location: last_node.location,
        version_id: version_id,
        passage_number: i + 1,
        start_location: first_node.location
      })
    end)

    {:ok, length(keys)}
  end

  @doc """
  Deletes a version.

  ## Examples

      iex> delete_version(version)
      {:ok, %Version{}}

      iex> delete_version(version)
      {:error, %Ecto.Changeset{}}

  """
  def delete_version(%Version{} = version) do
    Repo.delete(version)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking version changes.

  ## Examples

      iex> change_version(version)
      %Ecto.Changeset{data: %Version{}}

  """
  def change_version(%Version{} = version, attrs \\ %{}) do
    Version.changeset(version, attrs)
  end

  def create_xml_document!(%Version{} = version, attrs \\ %{}) do
    version
    |> Ecto.build_assoc(:xml_document)
    |> XmlDocument.changeset(attrs)
    |> Repo.insert!()
  end
end
