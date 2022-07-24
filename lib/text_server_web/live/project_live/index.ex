defmodule TextServerWeb.ProjectLive.Index do
  use TextServerWeb, :live_view

  alias TextServer.Accounts
  alias TextServer.Projects

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :project_collection, list_projects())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Project")
    |> assign(:project, Projects.get_project!(id))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Projects")
    |> assign(:project, nil)
  end

  defp apply_action(socket, :user_project_index, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id) |> TextServer.Repo.preload(:user_projects)

    socket
    |> assign(:page_title, "My Projects")
    |> assign(:project_collection, user.user_projects)
    |> assign(:user_id, user_id)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    {:ok, _} = Projects.delete_project(project)

    {:noreply, assign(socket, :project_collection, list_projects())}
  end

  defp list_projects do
    Projects.list_projects()
  end
end
