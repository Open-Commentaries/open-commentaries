defmodule TextServer.Works do
  @moduledoc """
  The Works context.
  """

  import Ecto.Query, warn: false

  alias TextServer.Repo
  alias TextServer.Works.Work

  def list_works do
    Work |> Repo.all()
  end

  def list_works(params) do
    Work |> Repo.paginate(params)
  end

  def list_works_for_urn(namespace, text_group, _params \\ [page: 1, page_size: 50]) do
    from(w in Work,
      where:
        fragment("? ->> ? = ?", w.urn, "namespace", ^namespace) and
          fragment("? ->> ? = ?", w.urn, "text_group", ^text_group)
    )
    |> Repo.all()
  end

  def search_works(term, params \\ []) do
    term = Regex.replace(~r/[^[:word:][:space:]]/u, term, "") <> ":*"

    Work
    |> where(
      [w],
      fragment("? @@ websearch_to_tsquery('english', ?)", w._search, ^term)
    )
    |> order_by([w],
      asc:
        fragment(
          "ts_rank_cd(?, websearch_to_tsquery('english', ?), 4)",
          w._search,
          ^term
        )
    )
    |> Repo.paginate(params)
  end

  @doc """
  Gets a single work.

  Raises `Ecto.NoResultsError` if the Work does not exist.

  ## Examples

      iex> get_work!(123)
      %Work{}

      iex> get_work!(456)
      ** (Ecto.NoResultsError)

  """
  def get_work!(id), do: Repo.get!(Work, id)

  def get_work(id), do: Repo.get(Work, id)

  def get_work_by_urn("urn:cts:" <> _rest = urn) when is_binary(urn) do
    case Work |> where([w], w.urn == ^urn) |> Repo.one() do
      nil -> {:error, urn}
      work -> {:ok, work}
    end
  end

  def get_work_by_urn(urn) when is_binary(urn) do
    get_work_by_urn("urn:cts:#{urn}")
  end

  def get_work_by_urn(%CTS.URN{} = urn) do
    case Work |> where([w], w.urn == ^urn) |> Repo.one() do
      nil -> {:error, urn}
      work -> {:ok, work}
    end
  end

  def get_work_cts_data(%Work{} = work) do
    cts_file = get_work_cts_file(work)
    cts_data_raw = File.read!(cts_file)
    DataSchema.to_struct(cts_data_raw, DataSchemas.Work.CTSDocument)
  end

  def get_work_cts_file(%Work{} = work) do
    path = CTS.base_cts_dir() <> "/#{get_work_dir(work.urn)}/__cts__.xml"

    if File.exists?(path) do
      path
    else
      :enoent
    end
  end

  def get_work_dir(%CTS.URN{} = urn) do
    "#{urn.text_group}/#{urn.work}"
  end

  @doc """
  Creates a work.

  ## Examples

      iex> create_work(%{field: value})
      {:ok, %Work{}}

      iex> create_work(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_work(attrs \\ %{}) do
    %Work{}
    |> Work.changeset(attrs)
    |> Repo.insert()
  end

  def find_or_create_work(attrs \\ %{}) do
    query = from(w in Work, where: w.urn == ^attrs[:urn])

    case Repo.one(query) do
      nil -> create_work(attrs)
      work -> {:ok, work}
    end
  end

  def upsert_work(attrs \\ %{}) do
    query = from(w in Work, where: w.urn == ^attrs[:urn])

    case Repo.one(query) do
      nil -> create_work(attrs)
      work -> update_work(work, attrs)
    end
  end

  @doc """
  Updates a work.

  ## Examples

      iex> update_work(work, %{field: new_value})
      {:ok, %Work{}}

      iex> update_work(work, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_work(%Work{} = work, attrs) do
    work
    |> Work.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a work.

  ## Examples

      iex> delete_work(work)
      {:ok, %Work{}}

      iex> delete_work(work)
      {:error, %Ecto.Changeset{}}

  """
  def delete_work(%Work{} = work) do
    Repo.delete(work)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking work changes.

  ## Examples

      iex> change_work(work)
      %Ecto.Changeset{data: %Work{}}

  """
  def change_work(%Work{} = work, attrs \\ %{}) do
    Work.changeset(work, attrs)
  end
end
