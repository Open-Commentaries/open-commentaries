defmodule TextServer.CollectionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TextServer.Collections` context.
  """

  @doc """
  Generate a unique collection repository.
  """
  def unique_collection_repository, do: "some repository#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique collection slug.
  """
  def unique_collection_slug, do: "some slug#{System.unique_integer([:positive])}"

  def unique_collection_urn, do: "urn:cts:#{System.unique_integer([:positive])}"

  @doc """
  Generate a collection.
  """
  def collection_fixture(attrs \\ %{}) do
    urn = unique_collection_urn()

    {:ok, collection} =
      attrs
      |> Enum.into(%{
        repository: unique_collection_repository(),
        slug: unique_collection_slug(),
        title: "some title",
        urn: urn,
        cts_urn: CTS.URN.parse(urn)
      })
      |> TextServer.Collections.create_collection()

    collection
  end
end
