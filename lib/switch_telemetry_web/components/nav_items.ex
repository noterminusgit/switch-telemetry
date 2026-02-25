defmodule SwitchTelemetryWeb.Components.NavItems do
  @moduledoc """
  Shared navigation item definitions used by both sidebar and mobile nav.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: SwitchTelemetryWeb.Endpoint,
    router: SwitchTelemetryWeb.Router,
    statics: SwitchTelemetryWeb.static_paths()

  @doc """
  Returns the list of standard navigation items.
  """
  def items do
    [
      %{path: ~p"/dashboards", icon: "hero-chart-bar-square", label: "Dashboards"},
      %{path: ~p"/devices", icon: "hero-server-stack", label: "Devices"},
      %{path: ~p"/streams", icon: "hero-signal", label: "Streams"},
      %{path: ~p"/alerts", icon: "hero-bell-alert", label: "Alerts"},
      %{path: ~p"/credentials", icon: "hero-key", label: "Credentials"},
      %{path: ~p"/settings", icon: "hero-cog-6-tooth", label: "Settings"}
    ]
  end

  @doc """
  Returns the admin-only navigation item.
  """
  def admin_item do
    %{path: ~p"/admin/users", icon: "hero-users", label: "Users"}
  end
end
