defmodule SwitchTelemetryWeb.PageController do
  use SwitchTelemetryWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboards")
    else
      redirect(conn, to: ~p"/users/log_in")
    end
  end
end
