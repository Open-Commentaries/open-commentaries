defmodule TextServer.Repo.Migrations.AddNodeTypeToTextNodes do
  use Ecto.Migration

  def change do
    alter table(:text_nodes) do
      add :node_type, :string, default: "para"
    end
  end
end
