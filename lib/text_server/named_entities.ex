defmodule TextServer.NamedEntities do
  import Ecto.Query, warn: false

  alias TextServer.NamedEntities.NamedEntityReference
  alias TextServer.Repo
  alias TextServer.NamedEntities.NamedEntity

  @moduledoc """
  This module provides the database interface for named entities.
  The entities themselves should be produced by running the
  appropriate serving over a given version, exemplar, or list
  of text nodes.

  Entity references have a foreign key constraint on entities,
  but the references and entities themselves are not
  constrained by version, exemplar, text node, etc.

  The thinking behind this is that entities will most often
  be looked up by URN, so we'd just be creating extra hassle
  and difficulty by imposing additional constraints.
  """

  @doc """
  Returns an Nx serving for named entity recognition/token classification in
  English-language texts.
  """
  def serving(:eng) do
    {:ok, model_info} =
      Bumblebee.load_model(
        {:local,
         to_string(:code.priv_dir(:text_server)) <> "/language_models/dslim/bert-base-NER"}
      )

    {:ok, tokenizer} =
      Bumblebee.load_tokenizer(
        {:local, to_string(:code.priv_dir(:text_server)) <> "/language_models/bert-base-cased"}
      )

    Bumblebee.Text.token_classification(model_info, tokenizer, aggregation: :same)
  end

  def serving(:grc), do: {:error, "Not implemented yet."}

  def serving(iso_code) do
    {:error, "Unknown ISO language code: #{iso_code}. Supported codes are :eng and :grc."}
  end

  def create_named_entity(attrs) do
    %NamedEntity{}
    |> NamedEntity.changeset(attrs)
    |> Repo.insert()
  end

  def create_named_entity_reference(%NamedEntity{} = named_entity, attrs) do
    Ecto.build_assoc(named_entity, :references)
    |> NamedEntityReference.changeset(attrs)
    |> Repo.insert()
  end

  def create_named_entity_reference(attrs) do
    %NamedEntityReference{}
    |> NamedEntityReference.changeset(attrs)
    |> Repo.insert()
  end

  def find_or_create_named_entity(attrs) do
    case %NamedEntity{}
         |> where([ne], ne.wikidata_id == ^attrs.wikidata_id and ne.label == ^attrs.label)
         |> Repo.one() do
      nil -> create_named_entity(attrs)
      entity -> {:ok, entity}
    end
  end

  def list_entities_for_urn(%CTS.URN{} = urn) do
    references =
      from(ref in NamedEntityReference,
        where: ^filter_by_urn(urn)
      )

    from(
      n in NamedEntity,
      join: ref in subquery(references),
      on: ref.named_entity_id == n.id
    )
    |> Repo.all()
  end

  def list_entities_for_urn(urn) when is_binary(urn),
    do: list_entities_for_urn(CTS.URN.parse(urn))

  defp filter_by_urn(%CTS.URN{} = urn) do
    urn
    |> Map.from_struct()
    |> Enum.reduce(dynamic(true), fn
      # If the value of a URN component is nil,
      # don't add it to the query. This is important,
      # because we might want to get all entities
      # for a given work, version, or examplar, in which
      # case the reference URN will have nil fragments,
      # but the entities will not.
      {_k, nil}, dynamic ->
        dynamic

      {:citations, [cit0, cit1]}, dynamic ->
        dynamic(
          [ref],
          ^dynamic and
            fragment("? \#> '{citations, 0}' = ?", ref.urn, ^cit0) and
            fragment("? \#> '{citations, 1}' = ?", ref.urn, ^cit1)
        )

      {:exemplar, v}, dynamic ->
        dynamic([ref], ^dynamic and fragment("? ->> 'exemplar' = ?", ref.urn, ^v))

      {:indexes, [ind0, ind1]}, dynamic ->
        dynamic(
          [ref],
          ^dynamic and
            fragment("? \#> '{indexes, 0}' = ?", ref.urn, ^ind0) and
            fragment("? \#> '{indexes, 1}' = ?", ref.urn, ^ind1)
        )

      {:namespace, v}, dynamic ->
        dynamic([ref], ^dynamic and fragment("? ->> 'namespace' = ?", ref.urn, ^v))

      {:subsections, [sub0, sub1]}, dynamic ->
        dynamic(
          [ref],
          ^dynamic and
            fragment("? \#> '{subsections, 0}' = ?", ref.urn, ^sub0) and
            fragment("? \#> '{subsections, 1}' = ?", ref.urn, ^sub1)
        )

      {:text_group, v}, dynamic ->
        dynamic([ref], ^dynamic and fragment("? ->> 'text_group' = ?", ref.urn, ^v))

      {:work, v}, dynamic ->
        dynamic([ref], ^dynamic and fragment("? ->> 'work' = ?", ref.urn, ^v))

      {:version, v}, dynamic ->
        dynamic([ref], ^dynamic and fragment("? ->> 'version' = ?", ref.urn, ^v))

      {_, _}, dynamic ->
        dynamic
    end)
  end
end
