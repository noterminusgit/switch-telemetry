defmodule SwitchTelemetryWeb.DashboardLive.Show do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetry.Metrics.QueryRouter

  @max_series_points 500

  @impl true
  def mount(%{"id" => dashboard_id}, _session, socket) do
    dashboard = Dashboards.get_dashboard!(dashboard_id)

    socket =
      socket
      |> assign(dashboard: dashboard, widget_data: %{}, page_title: dashboard.name)

    if connected?(socket) do
      subscribe_to_devices(dashboard)
      send(self(), :load_widget_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_widget_data, socket) do
    widget_data =
      socket.assigns.dashboard.widgets
      |> Map.new(fn widget ->
        series = load_widget_series(widget)
        {widget.id, series}
      end)

    {:noreply, assign(socket, widget_data: widget_data)}
  end

  # Real-time metric updates from PubSub
  def handle_info({type, device_id, metrics}, socket)
      when type in [:gnmi_metrics, :netconf_metrics] do
    widget_data =
      Enum.reduce(socket.assigns.dashboard.widgets, socket.assigns.widget_data, fn widget, acc ->
        if widget_uses_device?(widget, device_id) do
          updated = append_metrics(acc[widget.id], metrics, widget)
          Map.put(acc, widget.id, updated)
        else
          acc
        end
      end)

    {:noreply, assign(socket, widget_data: widget_data)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete_widget", %{"id" => widget_id}, socket) do
    widget = Enum.find(socket.assigns.dashboard.widgets, &(&1.id == widget_id))

    if widget do
      Dashboards.delete_widget(widget)
      dashboard = Dashboards.get_dashboard!(socket.assigns.dashboard.id)
      {:noreply, assign(socket, dashboard: dashboard)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 py-8">
      <header class="flex justify-between items-center mb-8">
        <div>
          <.link navigate={~p"/dashboards"} class="text-sm text-gray-500 hover:text-gray-700">
            &larr; Dashboards
          </.link>
          <h1 class="text-2xl font-bold text-gray-900 mt-1">{@dashboard.name}</h1>
          <p :if={@dashboard.description} class="text-sm text-gray-500 mt-1">{@dashboard.description}</p>
        </div>
      </header>

      <div class="grid grid-cols-12 gap-4">
        <%= for widget <- @dashboard.widgets do %>
          <div
            class={"col-span-#{widget_colspan(widget)} bg-white rounded-lg shadow p-4"}
          >
            <div class="flex justify-between items-start mb-2">
              <h3 class="text-sm font-medium text-gray-700">{widget.title}</h3>
              <button
                phx-click="delete_widget"
                phx-value-id={widget.id}
                data-confirm="Remove this widget?"
                class="text-gray-400 hover:text-red-600 text-xs"
              >
                &times;
              </button>
            </div>
            <.live_component
              module={SwitchTelemetryWeb.Components.TelemetryChart}
              id={widget.id}
              title={nil}
              series={Map.get(@widget_data, widget.id, [])}
              chart_type={widget.chart_type}
              width={widget_width(widget)}
              height={widget_height(widget)}
            />
          </div>
        <% end %>
      </div>

      <div :if={@dashboard.widgets == []} class="text-center py-12 text-gray-500">
        No widgets configured. Add widgets to see telemetry data.
      </div>
    </div>
    """
  end

  # --- Private ---

  defp subscribe_to_devices(dashboard) do
    dashboard.widgets
    |> Enum.flat_map(fn w -> Enum.map(w.queries || [], &Map.get(&1, "device_id")) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(fn device_id ->
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "device:#{device_id}")
    end)
  end

  defp load_widget_series(widget) do
    time_range = resolve_time_range(widget.time_range)

    (widget.queries || [])
    |> Enum.map(fn query ->
      device_id = Map.get(query, "device_id")
      path = Map.get(query, "path")

      data =
        if device_id && path do
          QueryRouter.query(device_id, path, time_range)
          |> Enum.map(fn row ->
            %{time: row.bucket, value: row.avg_value || 0.0}
          end)
        else
          []
        end

      %{
        label: Map.get(query, "label", path || "unknown"),
        color: Map.get(query, "color", "#3B82F6"),
        data: data
      }
    end)
  end

  defp resolve_time_range(%{"type" => "relative", "duration" => duration}) do
    now = DateTime.utc_now()
    offset = parse_duration(duration)
    %{start: DateTime.add(now, -offset, :second), end: now}
  end

  defp resolve_time_range(%{type: "relative", duration: duration}) do
    resolve_time_range(%{"type" => "relative", "duration" => duration})
  end

  defp resolve_time_range(_) do
    now = DateTime.utc_now()
    %{start: DateTime.add(now, -3600, :second), end: now}
  end

  defp parse_duration("5m"), do: 300
  defp parse_duration("15m"), do: 900
  defp parse_duration("1h"), do: 3_600
  defp parse_duration("6h"), do: 21_600
  defp parse_duration("24h"), do: 86_400
  defp parse_duration("7d"), do: 604_800
  defp parse_duration(_), do: 3_600

  defp widget_uses_device?(widget, device_id) do
    Enum.any?(widget.queries || [], fn q ->
      Map.get(q, "device_id") == device_id
    end)
  end

  defp append_metrics(nil, _metrics, _widget), do: []

  defp append_metrics(series, metrics, widget) do
    queries = widget.queries || []

    Enum.zip(series, queries)
    |> Enum.map(fn {s, query} ->
      path = Map.get(query, "path")

      relevant =
        metrics
        |> Enum.filter(fn m -> m.path == path end)
        |> Enum.map(fn m -> %{time: m.time, value: m[:value_float] || 0.0} end)

      %{s | data: trim_series(s.data ++ relevant, @max_series_points)}
    end)
  end

  defp trim_series(data, max) when length(data) > max do
    Enum.drop(data, length(data) - max)
  end

  defp trim_series(data, _), do: data

  defp widget_colspan(%{position: %{"w" => w}}), do: min(w, 12)
  defp widget_colspan(%{position: %{w: w}}), do: min(w, 12)
  defp widget_colspan(_), do: 6

  defp widget_width(%{position: %{"w" => w}}), do: w * 80
  defp widget_width(%{position: %{w: w}}), do: w * 80
  defp widget_width(_), do: 480

  defp widget_height(%{position: %{"h" => h}}), do: h * 60
  defp widget_height(%{position: %{h: h}}), do: h * 60
  defp widget_height(_), do: 240
end
