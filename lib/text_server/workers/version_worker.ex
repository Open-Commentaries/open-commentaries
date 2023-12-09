defmodule TextServer.Workers.VersionWorker do
  use Oban.Worker

  alias TextServer.Versions

  # We can implement different actions by passing additional
  # args to Oban when adding an item to the queue
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id} = _args}) do
    version = Versions.get_version!(id)

    parse(version)
  end

  defp parse(version) do
    # parse version, saving/updating TextNodes and TextElements
    case TextServer.Ingestion.Version.parse_version(version) do
      {:ok, version} ->
        {:ok, version}

      {:error, reason} ->
        IO.inspect(reason)
        :error
    end
  end
end
