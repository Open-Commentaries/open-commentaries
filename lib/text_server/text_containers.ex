defmodule TextServer.TextContainers do
  import Ecto.Query, warn: false
  alias TextServer.Repo

  alias TextServer.TextContainers.TextContainer

  def list_text_containers do
    Repo.all(TextContainer)
  end

  def create_text_container(attrs \\ %{}) do
    %TextContainer{}
    |> TextContainer.changeset(attrs)
    |> Repo.insert()
  end

  def find_or_create_text_container(attrs \\ %{}) do
    urn = Map.get(attrs, :urn, Map.get(attrs, "urn"))

    query = from(t in TextContainer, where: t.urn == ^urn)

    case Repo.one(query) do
      nil -> create_text_container(attrs)
      text_container -> {:ok, text_container}
    end
  end
end
