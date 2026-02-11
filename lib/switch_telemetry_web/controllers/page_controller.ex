defmodule SwitchTelemetryWeb.PageController do
  use SwitchTelemetryWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
