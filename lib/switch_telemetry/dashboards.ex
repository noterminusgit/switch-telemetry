defmodule SwitchTelemetry.Dashboards do
  @moduledoc """
  Context for managing user dashboards and widgets.
  """
  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Dashboards.{Dashboard, Widget}

  def list_dashboards do
    Repo.all(Dashboard)
  end

  def get_dashboard!(id) do
    Dashboard
    |> Repo.get!(id)
    |> Repo.preload(:widgets)
  end

  def create_dashboard(attrs) do
    %Dashboard{}
    |> Dashboard.changeset(attrs)
    |> Repo.insert()
  end

  def update_dashboard(%Dashboard{} = dashboard, attrs) do
    dashboard
    |> Dashboard.changeset(attrs)
    |> Repo.update()
  end

  def delete_dashboard(%Dashboard{} = dashboard) do
    Repo.delete(dashboard)
  end

  def add_widget(%Dashboard{} = dashboard, widget_attrs) do
    widget_attrs
    |> Map.put(:dashboard_id, dashboard.id)
    |> then(fn attrs ->
      %Widget{}
      |> Widget.changeset(attrs)
      |> Repo.insert()
    end)
  end

  def update_widget(%Widget{} = widget, attrs) do
    widget
    |> Widget.changeset(attrs)
    |> Repo.update()
  end

  def delete_widget(%Widget{} = widget) do
    Repo.delete(widget)
  end
end
