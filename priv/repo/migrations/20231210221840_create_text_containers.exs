defmodule TextServer.Repo.Migrations.CreateTextContainers do
  use Ecto.Migration

  def change do
    create table(:text_containers) do
      add :urn, :map
      add :location, {:array, :string}, null: false
      add :offset, :integer, null: false
      add :version_id, references(:versions, on_delete: :nothing), null: false

      timestamps()
    end

    create index(:text_containers, [:version_id])

    alter table(:text_nodes) do
      add :text_container_id, references(:text_containers, on_delete: :nothing)
    end

    create index(:text_nodes, [:text_container_id])
  end
end
