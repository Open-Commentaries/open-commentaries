defmodule TextServerWeb.ReadingEnvironment.TextNode do
  use TextServerWeb, :live_component

  attr :is_focused, :boolean, default: false
  attr :sibling_node, :map, default: nil
  attr :text_node, :map, required: true

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(is_focused: false)}
  end

  @impl true
  def render(assigns) do
    # NOTE: (charles) It's important, unfortunately, for the `for` statement
    # to be on one line so that we don't get extra spaces around elements.
    ~H"""
    <div class="flex w-full">
      <p
        class={["cursor-pointer", "mb-4", "px-4", "rounded", text_node_classes(@is_focused)]}
        phx-click="text-node-click"
        phx-target={@myself}
      >
        <span class="text-slate-500" title={"Location: #{@text_node.location |> Enum.join(".")}"}>
          <%= @text_node.location |> Enum.join(".") %>
        </span>
        <.text_element :for={{graphemes, tags} <- @text_node.graphemes_with_tags} tags={tags} text={Enum.join(graphemes)} />
      </p>

      <div :if={@sibling_node != nil} class="max-w-xl">
        <h3 class="font-bold text-md">
          <%= @sibling_node.version.label %>
        </h3>
        <p class="mb-4 px-4 whitespace-normal">
          <.text_element :for={{graphemes, tags} <- @sibling_node.graphemes_with_tags} tags={tags} text={Enum.join(graphemes)} />
        </p>
      </div>
    </div>
    """
  end

  @spec text_node_classes(boolean()) :: String.t()
  defp text_node_classes(is_focused) do
    if is_focused do
      "ring-4"
    else
      "hover:ring-4"
    end
  end

  @impl true
  def handle_event("text-node-click", _, socket) do
    send(self(), {:focused_text_node, socket.assigns.text_node})
    {:noreply, socket}
  end

  attr :tags, :list, default: []
  attr :text, :string

  def text_element(assigns) do
    tags = assigns[:tags]

    assigns =
      assign(
        assigns,
        :classes,
        tags
        |> Enum.map(&tag_classes/1)
        |> Enum.join(" ")
      )

    cond do
      Enum.member?(tags |> Enum.map(& &1.name), "comment") ->
        assigns =
          assign(
            assigns,
            :comments,
            tags
            |> Enum.filter(&(&1.name == "comment"))
            |> Enum.map(& &1.metadata[:id])
            |> Jason.encode!()
          )

        ~H"""
        <span class={@classes} phx-click="highlight-comments" phx-value-comments={@comments}><%= @text %></span>
        """

      Enum.member?(tags |> Enum.map(& &1.name), "image") ->
        assigns =
          assign(
            assigns,
            src:
              tags |> Enum.find(&(&1.name == "image")) |> Map.get(:metadata, %{}) |> Map.get(:src)
          )

        ~H"<img class={@classes} src={@src} />"

      Enum.member?(tags |> Enum.map(& &1.name), "link") ->
        assigns =
          assign(
            assigns,
            :src,
            tags |> Enum.find(&(&1.name == "link")) |> Map.get(:metadata, %{}) |> Map.get(:src)
          )

        ~H"""
        <a class={@classes} href={@src}><%= @text %></a>
        """

      Enum.member?(tags |> Enum.map(& &1.name), "note") ->
        assigns =
          assign(
            assigns,
            :footnote,
            tags |> Enum.find(&(&1.name == "note")) |> Map.get(:metadata, %{})
          )

        # NOTE: This element must be on a single line because we're preserving paragraph breaks from the original docx.
        ~H"""
        <span class={@classes}><%= @text %><a href={"#_fn-#{@footnote[:id]}"} id={"_fn-ref-#{@footnote[:id]}"}><sup>*</sup></a></span>
        """

      true ->
        ~H"<span class={@classes}><%= @text %></span>"
    end
  end

  defp tag_classes(tag) do
    case tag.name do
      "comment" -> "bg-blue-200 cursor-pointer"
      "emph" -> "italic"
      "image" -> "image mt-10"
      "link" -> "link font-bold underline hover:opacity-75 visited:opacity-60"
      "strong" -> "font-bold"
      "underline" -> "underline"
      _ -> tag.name
    end
  end
end
