defmodule SwitchTelemetry.Dashboards do
  @moduledoc """
  Context for managing user dashboards and widgets.
  """
  import Ecto.Query
  require Logger

  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Collector.{Subscription, SubscriptionPaths}
  alias SwitchTelemetry.Dashboards.{Dashboard, Widget}
  alias SwitchTelemetry.Devices.Device

  @spec list_dashboards() :: [Dashboard.t()]
  def list_dashboards do
    Repo.all(Dashboard)
  end

  @spec get_dashboard!(String.t()) :: Dashboard.t()
  def get_dashboard!(id) do
    Dashboard
    |> Repo.get!(id)
    |> Repo.preload(:widgets)
  end

  @spec create_dashboard(map()) :: {:ok, Dashboard.t()} | {:error, Ecto.Changeset.t()}
  def create_dashboard(attrs) do
    %Dashboard{}
    |> Dashboard.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_dashboard(Dashboard.t(), map()) ::
          {:ok, Dashboard.t()} | {:error, Ecto.Changeset.t()}
  def update_dashboard(%Dashboard{} = dashboard, attrs) do
    dashboard
    |> Dashboard.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_dashboard(Dashboard.t()) :: {:ok, Dashboard.t()} | {:error, Ecto.Changeset.t()}
  def delete_dashboard(%Dashboard{} = dashboard) do
    Repo.delete(dashboard)
  end

  @spec add_widget(Dashboard.t(), map()) :: {:ok, Widget.t()} | {:error, Ecto.Changeset.t()}
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

  @spec update_widget(Widget.t(), map()) :: {:ok, Widget.t()} | {:error, Ecto.Changeset.t()}
  def update_widget(%Widget{} = widget, attrs) do
    widget
    |> Widget.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_widget(Widget.t()) :: {:ok, Widget.t()} | {:error, Ecto.Changeset.t()}
  def delete_widget(%Widget{} = widget) do
    Repo.delete(widget)
  end

  @doc "Clones a dashboard and all its widgets. Returns the new dashboard."
  @spec clone_dashboard(Dashboard.t(), String.t() | nil) ::
          {:ok, Dashboard.t()} | {:error, Ecto.Changeset.t()}
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
  @spec list_device_options() :: [{String.t(), String.t()}]
  def list_device_options do
    from(d in Device,
      select: {d.hostname, d.id},
      order_by: d.hostname
    )
    |> Repo.all()
  end

  @doc """
  Returns devices grouped by platform for `<optgroup>` rendering in widget picker.

  Returns `[{platform_label, [{hostname, id}]}]` sorted alphabetically by platform.
  """
  @spec list_devices_for_widget_picker() :: [{String.t(), [{String.t(), String.t()}]}]
  def list_devices_for_widget_picker do
    from(d in Device,
      select: {d.platform, d.hostname, d.id},
      order_by: [d.platform, d.hostname]
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_platform, hostname, id} -> {hostname, id} end)
    |> Enum.map(fn {platform, devices} -> {format_platform(platform), devices} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc """
  Returns metric paths grouped by category for a device's enabled subscriptions.

  Returns `[{category_label, [{path, path}]}]` sorted alphabetically by category.
  Returns `[]` if the device doesn't exist or has no enabled subscriptions.
  """
  @spec list_paths_for_device(String.t()) :: [{String.t(), [{String.t(), String.t()}]}]
  def list_paths_for_device(device_id) do
    case Repo.get(Device, device_id) do
      nil ->
        Logger.debug("list_paths_for_device(#{device_id}): device not found")
        []

      device ->
        subscribed_paths = get_subscribed_paths(device_id)

        Logger.debug(
          "list_paths_for_device(#{device_id}): device=#{device.hostname}, " <>
            "platform=#{device.platform}, subscribed_paths=#{inspect(subscribed_paths)}"
        )

        if subscribed_paths == [] do
          []
        else
          known_paths = SubscriptionPaths.list_paths(device.platform, device.model)
          category_map = Map.new(known_paths, fn entry -> {entry.path, entry.category} end)

          subscribed_paths
          |> Enum.map(fn path ->
            category = Map.get(category_map, path, "other")
            {category, path}
          end)
          |> Enum.group_by(&elem(&1, 0), fn {_cat, path} -> {path, path} end)
          |> Enum.map(fn {category, paths} ->
            {humanize_category(category), Enum.sort(paths)}
          end)
          |> Enum.sort_by(&elem(&1, 0))
        end
    end
  end

  defp get_subscribed_paths(device_id) do
    from(s in Subscription,
      where: s.device_id == ^device_id and s.enabled == true,
      select: s.paths
    )
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp format_platform(:cisco_iosxr), do: "Cisco IOS-XR"
  defp format_platform(:cisco_iosxe), do: "Cisco IOS-XE"
  defp format_platform(:cisco_nxos), do: "Cisco NX-OS"
  defp format_platform(:juniper_junos), do: "Juniper Junos"
  defp format_platform(:arista_eos), do: "Arista EOS"
  defp format_platform(:nokia_sros), do: "Nokia SR OS"

  defp format_platform(other),
    do: other |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp humanize_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc "Returns a changeset for dashboard editing."
  @spec change_dashboard(Dashboard.t(), map()) :: Ecto.Changeset.t()
  def change_dashboard(%Dashboard{} = dashboard, attrs \\ %{}) do
    Dashboard.changeset(dashboard, attrs)
  end

  @doc "Returns a changeset for widget editing."
  @spec change_widget(Widget.t(), map()) :: Ecto.Changeset.t()
  def change_widget(%Widget{} = widget, attrs \\ %{}) do
    Widget.changeset(widget, attrs)
  end

  @doc "Gets a single widget."
  @spec get_widget!(String.t()) :: Widget.t()
  def get_widget!(id), do: Repo.get!(Widget, id)

  defp generate_id(prefix) do
    prefix <> Base.encode32(:crypto.strong_rand_bytes(15), case: :lower, padding: false)
  end

  defp has_string_keys?(map) when map_size(map) == 0, do: false

  defp has_string_keys?(map) do
    map |> Map.keys() |> hd() |> is_binary()
  end
end
