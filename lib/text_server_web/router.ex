defmodule TextServerWeb.Router do
  use TextServerWeb, :router

  import TextServerWeb.UserAuth
  import TextServerWeb.Plugs.API, only: [authenticate_api_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TextServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug TextServerWeb.Plugs.API
  end

  scope "/api", TextServerWeb do
    pipe_through [:api, :authenticate_api_user]

    get "/versions/:id/download", VersionController, :download
  end

  # TODO: Better handling of user uploads. This is not
  # an immediate goal: we can accomplish far more by
  # having admins fork the repository and tell it what
  # files to ingest.
  scope "/", TextServerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :with_authenticated_user,
      on_mount: [{TextServerWeb.UserAuth, :ensure_authenticated}] do
      live "/collections/new", CollectionLive.Index, :new
      live "/collections/:id/edit", CollectionLive.Index, :edit
      live "/collections/:id/show/edit", CollectionLive.Show, :edit

      live "/languages/new", LanguageLive.Index, :new
      live "/languages/:id/edit", LanguageLive.Index, :edit
      live "/languages/:id/show/edit", LanguageLive.Show, :edit

      live "/text_groups/new", TextGroupLive.Index, :new
      live "/text_groups/:id/edit", TextGroupLive.Index, :edit
      live "/text_groups/:id/show/edit", TextGroupLive.Show, :edit

      live "/text_nodes/new", TextNodeLive.Index, :new
      live "/text_nodes/:id/edit", TextNodeLive.Index, :edit
      live "/text_nodes/:id/show/edit", TextNodeLive.Show, :edit

      live "/versions/:id/edit", VersionLive.Edit, :edit
      live "/versions/:id/show/edit", VersionLive.Show, :edit

      live "/works/new", WorkLive.New, :new
      live "/works/:id/edit", WorkLive.Index, :edit
      live "/works/:id/show/edit", WorkLive.Show, :edit

      scope "/:user_id" do
        live "/projects", ProjectLive.UserProjectIndex, :index
        live "/projects/:id/versions/new", VersionLive.New, :new
      end
    end
  end

  scope "/", TextServerWeb do
    pipe_through [:browser, :require_authenticated_user, :require_project_admin]

    live_session :project_with_admin, on_mount: [{TextServerWeb.UserAuth, :mount_current_user}] do
      live "/projects/:project_id/edit", ProjectLive.Edit, :edit
    end
  end

  scope "/", TextServerWeb do
    pipe_through :browser

    get "/", PageController, :home

    # these logged-out routes must come last, otherwise they
    # match on /{resource}/new
    live_session :default, on_mount: [{TextServerWeb.UserAuth, :mount_current_user}] do
      live "/collections", CollectionLive.Index, :index
      live "/collections/:id", CollectionLive.Show, :show

      live "/exemplars", ExemplarLive.Index, :index
      live "/exemplars/:id", ExemplarLive.Show, :show

      live "/languages", LanguageLive.Index, :index
      live "/languages/:id", LanguageLive.Show, :show

      live "/projects", ProjectLive.Index, :index
      live "/projects/:id", ProjectLive.Show, :show

      live "/text_groups", TextGroupLive.Index, :index
      live "/text_groups/:id", TextGroupLive.Show, :show

      live "/text_nodes", TextNodeLive.Index, :index
      live "/text_nodes/:id", TextNodeLive.Show, :show

      live "/versions", VersionLive.Index, :index
      live "/versions/:id", VersionLive.Show, :show

      live "/works", WorkLive.Index, :index
      live "/works/:id", WorkLive.Show, :show

      live "/read", ReadLive.Index, :index
      live "/read/:collection", ReadLive.Index, :collection
      live "/read/:collection/:text_group", ReadLive.Index, :text_group
      live "/read/:collection/:text_group/:work", ReadLive.Index, :work
      live "/read/:collection/:text_group/:work/:version", ReadLive.Reader, :reader
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:components, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TextServerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TextServerWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TextServerWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", AccountLive.UserRegistrationLive, :new
      live "/users/log_in", AccountLive.UserLoginLive, :new
      live "/users/reset_password", AccountLive.UserForgotPasswordLive, :new
      live "/users/reset_password/:token", AccountLive.UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TextServerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TextServerWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", AccountLive.UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", AccountLive.UserSettingsLive, :confirm_email

      live "/:user_id/projects/new", ProjectLive.New, :new
      live "/projects/:id/exemplars/edit", ProjectLive.EditExemplars, :edit
    end
  end

  scope "/", TextServerWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TextServerWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", AccountLive.UserConfirmationLive, :edit
      live "/users/confirm", AccountLive.UserConfirmationInstructionsLive, :new
    end
  end
end
