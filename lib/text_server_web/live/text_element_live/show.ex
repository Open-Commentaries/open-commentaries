defmodule TextServerWeb.TextElementLive.Show do
  use TextServerWeb, :live_view

  alias TextServer.TextElements

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:text_element, TextElements.get_text_element!(id))}
  end

  defp page_title(:show), do: "Show Text element"
  defp page_title(:edit), do: "Edit Text element"
end
