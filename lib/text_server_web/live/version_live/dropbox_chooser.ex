defmodule TextServerWeb.VersionLive.DropboxChooser do
  use TextServerWeb, :live_component

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="prose prose-h2 text-lg">Select a file to watch from Dropbox</h2>
      <div id="dropbox-chooser-container" phx-hook="DropboxChooserHook" phx-update="ignore" />
      <script type="text/javascript" src="https://www.dropbox.com/static/api/2/dropins.js" id="dropboxjs" data-app-key="zra9naz8fn5ijmu">
      </script>
    </section>
    """
  end
end
