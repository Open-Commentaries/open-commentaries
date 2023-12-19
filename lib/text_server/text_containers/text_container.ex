defmodule TextServer.TextContainers.TextContainer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "text_containers" do
    field :location, {:array, :string}
    field :offset, :integer
    field :urn, TextServer.Ecto.Types.CTS_URN

    belongs_to :version, TextServer.Versions.Version

    has_many :text_nodes, TextServer.TextNodes.TextNode

    timestamps()
  end

  @doc false
  def changeset(text_container, attrs) do
    text_container
    |> cast(attrs, [:urn, :location, :offset, :version_id])
    |> validate_required([:location, :offset, :version_id])
    |> unique_constraint([:urn])
    |> assoc_constraint(:version)
  end
end
