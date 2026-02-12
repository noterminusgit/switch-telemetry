defmodule SwitchTelemetryWeb.Router do
  use SwitchTelemetryWeb, :router

  import SwitchTelemetryWeb.UserAuth,
    only: [
      fetch_current_user: 2,
      redirect_if_user_is_authenticated: 2,
      require_authenticated_user: 2,
      require_admin: 2
    ]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SwitchTelemetryWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-eval'; " <>
          "style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data: blob:; " <>
          "font-src 'self' data:; " <>
          "connect-src 'self' wss: ws:; " <>
          "frame-ancestors 'none'"
    }

    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  ## Authentication routes (no auth required, redirect if already logged in)
  scope "/", SwitchTelemetryWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
  end

  ## Authenticated routes (non-LiveView)
  scope "/", SwitchTelemetryWeb do
    pipe_through [:browser, :require_authenticated_user]

    delete "/users/log_out", UserSessionController, :delete
  end

  ## Authenticated LiveViews
  live_session :authenticated,
    on_mount: [{SwitchTelemetryWeb.UserAuth, :ensure_authenticated}] do
    scope "/", SwitchTelemetryWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/dashboards", DashboardLive.Index, :index
      live "/dashboards/new", DashboardLive.Index, :new
      live "/dashboards/:id", DashboardLive.Show, :show
      live "/dashboards/:id/edit", DashboardLive.Show, :edit
      live "/dashboards/:id/widgets/new", DashboardLive.Show, :add_widget
      live "/dashboards/:id/widgets/:widget_id/edit", DashboardLive.Show, :edit_widget

      live "/devices", DeviceLive.Index, :index
      live "/devices/new", DeviceLive.Index, :new
      live "/devices/:id", DeviceLive.Show, :show

      live "/alerts", AlertLive.Index, :index
      live "/alerts/rules/new", AlertLive.Index, :new_rule
      live "/alerts/rules/:id/edit", AlertLive.Index, :edit_rule
      live "/alerts/channels", AlertLive.Index, :channels
      live "/alerts/channels/new", AlertLive.Index, :new_channel
      live "/alerts/channels/:id/edit", AlertLive.Index, :edit_channel

      live "/settings", UserLive.Settings, :edit
    end
  end

  ## Admin LiveViews
  live_session :admin,
    on_mount: [{SwitchTelemetryWeb.UserAuth, :ensure_admin}] do
    scope "/admin", SwitchTelemetryWeb do
      pipe_through [:browser, :require_authenticated_user, :require_admin]

      live "/users", UserLive.Index, :index
    end
  end

  ## Public routes
  scope "/", SwitchTelemetryWeb do
    pipe_through :browser

    get "/", PageController, :home
  end
end
