defmodule TextServerWeb.ReadLive.Reader.Navigation do
  use TextServerWeb, :component

  # `passages` is a chunked list of lists, where each
  # item is a tuple of the form `{{top_level_citation, second_level_citation}, page_number}`
  attr :passage_refs, :list
  attr :unit_labels, :list

  def navigation_menu(assigns) do
    ~H"""
    <nav>
      <ul class="menu bg-base-200 w-56 rounded">
        <%= for group <- @passage_refs do %>
          <li>
            <details>
              <summary><%= List.first(@unit_labels) |> :string.titlecase() %> <%= List.first(group) |> elem(0) |> elem(0) %></summary>
              <ul class="overflow-y-auto max-h-48">
              <%!-- This will work for 3-level texts like Pausanias; what about 1- or 2-level texts? --%>
                <%= for passage <- group do %>
                  <li>
                    <a href={"?page=#{elem(passage, 1)}"}>
                      <%= List.first(@unit_labels) |> :string.titlecase() %>
                      <%= List.first(group) |> elem(0) |> elem(0) %>,
                      <%= Enum.at(@unit_labels, 1) |> :string.titlecase() %>
                      <%= elem(passage, 0) |> elem(1) %>
                    </a>
                  </li>
                <% end %>
              </ul>
            </details>
          </li>
        <% end %>
      </ul>
    </nav>
    """
  end
end