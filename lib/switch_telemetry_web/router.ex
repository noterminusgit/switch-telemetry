defmodule SwitchTelemetryWeb.Router do
  use SwitchTelemetryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SwitchTelemetryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SwitchTelemetryWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/dashboards", DashboardLive.Index, :index
    live "/dashboards/new", DashboardLive.Index, :new
    live "/dashboards/:id", DashboardLive.Show, :show

    live "/devices", DeviceLive.Index, :index
    live "/devices/new", DeviceLive.Index, :new
    live "/devices/:id", DeviceLive.Show, :show
  end
end
