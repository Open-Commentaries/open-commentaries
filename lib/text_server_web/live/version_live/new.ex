defmodule TextServerWeb.VersionLive.New do
  use TextServerWeb, :live_view

  alias TextServer.Versions.Version
  alias TextServer.Projects
  alias TextServer.Repo

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(
       version: %Version{} |> Repo.preload(:language),
       page_title: "Create version",
       project: get_project!(params["id"]),
       selected_work: nil,
       works: []
     )}
  end

  @impl true
  def handle_params(_params, _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(event_name, _params, socket) do
    IO.puts("Should probably handle the event called #{event_name}...")
    {:noreply, socket}
  end

  defp get_project!(id) do
    Projects.get_project!(id)
  end
end
