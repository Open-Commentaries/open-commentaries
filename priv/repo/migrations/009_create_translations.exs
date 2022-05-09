defmodule TextServer.Repo.Migrations.CreateTranslations do
  use Ecto.Migration

  def change do
    create table(:translations) do
      add :description, :string
      add :slug, :string
      add :title, :string
      add :urn, :string
      add :work_id, references(:works, on_delete: :nothing)

      timestamps()
    end

    create index(:translations, [:work_id])
  end
end
