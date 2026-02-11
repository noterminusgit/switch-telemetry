defmodule SwitchTelemetry.Dashboards do
  @moduledoc """
  Context for managing user dashboards and widgets.
  """
  import Ecto.Query

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
    key = if has_string_keys?(widget_attrs), do: "dashboard_id", else: :dashboard_id

    widget_attrs
    |> Map.put(key, dashboard.id)
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

  @doc "Clones a dashboard and all its widgets. Returns the new dashboard."
  def clone_dashboard(%Dashboard{} = dashboard, created_by \\ nil) do
    dashboard = Repo.preload(dashboard, :widgets)
    new_id = generate_id("dash_")

    clone_attrs = %{
      id: new_id,
      name: "Copy of #{dashboard.name}",
      description: dashboard.description,
      layout: dashboard.layout,
      refresh_interval_ms: dashboard.refresh_interval_ms,
      is_public: false,
      tags: dashboard.tags || [],
      created_by: created_by
    }

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:dashboard, Dashboard.changeset(%Dashboard{}, clone_attrs))
    |> Ecto.Multi.run(:widgets, fn _repo, %{dashboard: new_dash} ->
      widgets =
        Enum.map(dashboard.widgets || [], fn widget ->
          widget_attrs = %{
            id: generate_id("wgt_"),
            dashboard_id: new_dash.id,
            title: widget.title,
            chart_type: widget.chart_type,
            position: widget.position,
            time_range: widget.time_range,
            queries: widget.queries
          }

          %Widget{}
          |> Widget.changeset(widget_attrs)
          |> Repo.insert!()
        end)

      {:ok, widgets}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{dashboard: dashboard}} ->
        {:ok, Repo.preload(dashboard, :widgets)}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc "Returns device options [{hostname, id}] for widget query builder."
  def list_device_options do
    from(d in SwitchTelemetry.Devices.Device,
      select: {d.hostname, d.id},
      order_by: d.hostname
    )
    |> Repo.all()
  end

  @doc "Returns distinct metric paths seen for a device."
  def list_device_metric_paths(device_id) do
    from(m in "metrics",
      where: m.device_id == ^device_id,
      distinct: true,
      select: m.path,
      order_by: m.path,
      limit: 500
    )
    |> Repo.all()
  end

  @doc "Returns a changeset for dashboard editing."
  def change_dashboard(%Dashboard{} = dashboard, attrs \\ %{}) do
    Dashboard.changeset(dashboard, attrs)
  end

  @doc "Returns a changeset for widget editing."
  def change_widget(%Widget{} = widget, attrs \\ %{}) do
    Widget.changeset(widget, attrs)
  end

  @doc "Gets a single widget."
  def get_widget!(id), do: Repo.get!(Widget, id)

  defp generate_id(prefix) do
    prefix <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end

  defp has_string_keys?(map) when map_size(map) == 0, do: false

  defp has_string_keys?(map) do
    map |> Map.keys() |> hd() |> is_binary()
  end
end
