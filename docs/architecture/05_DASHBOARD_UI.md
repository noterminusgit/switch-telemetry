# 05: Dashboard UI (LiveView + VegaLite/Tucan)

## VegaLite/Tucan Overview

**VegaLite** is an Elixir binding to the Vega-Lite visualization grammar. It generates declarative JSON specifications describing charts. **Tucan** is a high-level plotting library built on VegaLite that provides a seaborn-style API for common chart types.

Charts are rendered **client-side** by the Vega JavaScript runtime. The Elixir server generates a JSON spec, pushes it to the browser via a LiveView hook, and Vega renders interactive SVG/Canvas.

**Packages**:
- `{:vega_lite, "~> 0.1"}` -- Vega-Lite spec builder (1M+ hex downloads)
- `{:tucan, "~> 0.5"}` -- High-level charting API
- npm: `vega`, `vega-lite`, `vega-embed` -- Client-side rendering runtime

### Available Chart Types via Tucan

| Function | Purpose | Telemetry Use Case |
|---|---|---|
| `Tucan.lineplot/3` | Connected line chart | Interface bandwidth over time |
| `Tucan.bar/3` | Vertical bar chart | Top-N device comparisons |
| `Tucan.area/3` | Shaded area chart | Bandwidth utilization fill |
| `Tucan.scatter/3` | Scatter points | Discrete events (flaps, errors) |
| `Tucan.step/3` | Step chart | Interface status changes (up/down) |
| `Tucan.heatmap/3` | Color-coded matrix | Error density by device and hour |
| `Tucan.histogram/3` | Distribution | Latency distributions |
| `Tucan.boxplot/3` | Box-and-whisker | Metric spread per device |

### VegaLite Encodings (used under the hood)

| Encoding | Type | Use Case |
|---|---|---|
| `:temporal` | DateTime fields | Time axis for all charts |
| `:quantitative` | Numeric fields | Value axes (bps, %, count) |
| `:nominal` | Categorical strings | Device names, interface labels |
| `:ordinal` | Ordered categories | Severity levels, priority |

### Built-in Interactivity

Unlike server-side SVG approaches, VegaLite renders provide:
- **Tooltips** -- hover over any data point to see exact values
- **Zoom/Pan** -- scroll to zoom, drag to pan time ranges
- **Selections** -- click or brush to highlight subsets of data
- **Cross-filtering** -- link multiple charts so selecting in one filters others

## Dashboard Architecture

### User-Configurable Dashboards

Users create dashboards composed of widgets. Each widget defines:
- Which device(s) and metric path(s) to display
- Chart type (line, bar, area, etc.)
- Time range (relative like "last 1h" or absolute)
- Aggregation (raw, rate, avg, max, min)
- Visual options (colors, labels, grid position)

### Data Flow in LiveView

```
  mount/3                  PubSub                     User Interaction
     │                       │                              │
     ▼                       ▼                              ▼
 ┌─────────────────────────────────────────────────────────────┐
 │                    DashboardLive                            │
 │                                                             │
 │  1. Load dashboard config from DB                          │
 │  2. For each widget:                                       │
 │     a. Query TimescaleDB for initial historical data       │
 │     b. Subscribe to PubSub for real-time updates           │
 │  3. Build VegaLite specs from data (via Tucan)             │
 │  4. Push specs to browser via push_event/3                 │
 │                                                             │
 │  handle_info({:gnmi_metrics, device_id, metrics})          │
 │     → append new points to relevant widget data            │
 │     → rebuild VegaLite spec                                │
 │     → push updated spec to Vega hook                       │
 │                                                             │
 │  handle_event("change_time_range", ...)                    │
 │     → re-query TimescaleDB for new range                   │
 │     → choose raw table vs continuous aggregate based on    │
 │       range duration                                       │
 │                                                             │
 │  handle_event("add_widget", ...)                           │
 │     → update dashboard config in DB                        │
 │     → subscribe to new PubSub topics                       │
 │     → query initial data                                   │
 └─────────────────────────────────────────────────────────────┘
```

### JavaScript Hook Setup

Charts require a VegaLite hook registered with LiveView.

**Install npm packages** (`assets/`):
```bash
npm install --save vega vega-lite vega-embed
```

**Hook** (`assets/js/hooks/vega_lite.js`):
```javascript
import vegaEmbed from "vega-embed";

const VegaLiteHook = {
  mounted() {
    this.chartId = this.el.getAttribute("data-chart-id");

    this.handleEvent(`vega_lite:${this.chartId}:update`, ({ spec }) => {
      vegaEmbed(this.el, spec, {
        actions: false,
        renderer: "svg",
        tooltip: { theme: "dark" }
      })
        .then((result) => { this.view = result.view; })
        .catch((error) => console.error("VegaLite render error:", error));
    });
  },

  destroyed() {
    if (this.view) {
      this.view.finalize();
    }
  }
};

export { VegaLiteHook };
```

**Register** in `assets/js/app.js`:
```javascript
import { VegaLiteHook } from "./hooks/vega_lite";

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { VegaLiteHook }
});
```

### Chart Component Example

```elixir
defmodule SwitchTelemetryWeb.Components.TelemetryChart do
  @moduledoc """
  Reusable VegaLite/Tucan chart component for telemetry data.
  Builds Vega-Lite specs and pushes them to the browser via hooks.
  """
  use SwitchTelemetryWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> push_chart_spec()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="telemetry-chart">
      <h3 class="text-sm font-medium text-gray-700"><%= @title %></h3>
      <div
        id={"chart-#{@id}"}
        phx-hook="VegaLiteHook"
        phx-update="ignore"
        data-chart-id={@id}
        style={"width: #{@width}px; height: #{@height}px;"}
      />
    </div>
    """
  end

  defp push_chart_spec(socket) do
    %{id: id, series: series, chart_type: chart_type, width: width, height: height} =
      socket.assigns

    spec = build_spec(series, chart_type, width, height)
    push_event(socket, "vega_lite:#{id}:update", %{spec: spec})
  end

  defp build_spec(series, chart_type, width, height) do
    data = flatten_series(series)

    if data == [] do
      empty_spec(width, height)
    else
      chart_fn = chart_function(chart_type)

      data
      |> chart_fn.("time", "value", width: width, height: height, tooltip: true)
      |> Tucan.color_by("label")
      |> VegaLite.to_spec()
    end
  end

  defp chart_function(:line), do: &Tucan.lineplot/4
  defp chart_function(:area), do: &Tucan.area/4
  defp chart_function(:bar), do: &Tucan.bar/4
  defp chart_function(:scatter), do: &Tucan.scatter/4
  defp chart_function(_), do: &Tucan.lineplot/4

  defp flatten_series(series) do
    Enum.flat_map(series, fn s ->
      Enum.map(s.data, fn point ->
        %{
          "time" => DateTime.to_iso8601(point.time),
          "value" => point.value,
          "label" => s.label
        }
      end)
    end)
  end

  defp empty_spec(width, height) do
    VegaLite.new(width: width, height: height, title: "No data")
    |> VegaLite.to_spec()
  end
end
```

### Dashboard LiveView

```elixir
defmodule SwitchTelemetryWeb.DashboardLive do
  use SwitchTelemetryWeb, :live_view

  alias SwitchTelemetry.{Dashboards, Metrics}

  @impl true
  def mount(%{"id" => dashboard_id}, _session, socket) do
    dashboard = Dashboards.get_dashboard!(dashboard_id)

    socket =
      socket
      |> assign(dashboard: dashboard)
      |> assign(widget_data: %{})

    if connected?(socket) do
      # Subscribe to PubSub for each device referenced by widgets
      dashboard.widgets
      |> Enum.flat_map(fn w -> Enum.map(w.queries, & &1.device_id) end)
      |> Enum.uniq()
      |> Enum.each(fn device_id ->
        Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "device:#{device_id}")
      end)

      # Load initial data for each widget
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

  # Real-time update from PubSub
  def handle_info({:gnmi_metrics, device_id, metrics}, socket) do
    widget_data =
      socket.assigns.dashboard.widgets
      |> Enum.reduce(socket.assigns.widget_data, fn widget, acc ->
        if widget_uses_device?(widget, device_id) do
          updated_series = append_metrics_to_series(acc[widget.id], metrics, widget)
          Map.put(acc, widget.id, updated_series)
        else
          acc
        end
      end)

    {:noreply, assign(socket, widget_data: widget_data)}
  end

  def handle_info({:netconf_metrics, device_id, metrics}, socket) do
    handle_info({:gnmi_metrics, device_id, metrics}, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dashboard">
      <header class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold"><%= @dashboard.name %></h1>
        <button phx-click="add_widget" class="btn btn-primary">Add Widget</button>
      </header>

      <div class="grid grid-cols-12 gap-4">
        <%= for widget <- @dashboard.widgets do %>
          <div
            class={"col-span-#{widget.position.w} row-span-#{widget.position.h}"}
            style={"grid-column: #{widget.position.x + 1} / span #{widget.position.w}; grid-row: #{widget.position.y + 1} / span #{widget.position.h};"}
          >
            <.live_component
              module={SwitchTelemetryWeb.Components.TelemetryChart}
              id={widget.id}
              title={widget.title}
              widget={widget}
              series={Map.get(@widget_data, widget.id, [])}
              chart_type={widget.chart_type}
              width={widget_width(widget)}
              height={widget_height(widget)}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # --- Private helpers ---

  defp load_widget_series(widget) do
    time_range = resolve_time_range(widget.time_range)

    Enum.map(widget.queries, fn query ->
      data = Metrics.get_time_series(
        query.device_id,
        query.path,
        query[:bucket_size] || "1m",
        time_range
      )

      %{
        label: query.label,
        color: query.color,
        data: Enum.map(data, fn row ->
          %{time: row.bucket, value: row.avg || 0.0}
        end)
      }
    end)
  end

  defp resolve_time_range(%{type: :relative, duration: duration}) do
    now = DateTime.utc_now()
    offset = parse_duration(duration)
    %{start: DateTime.add(now, -offset, :second), end: now}
  end

  defp parse_duration("5m"), do: 300
  defp parse_duration("15m"), do: 900
  defp parse_duration("1h"), do: 3600
  defp parse_duration("6h"), do: 21600
  defp parse_duration("24h"), do: 86400
  defp parse_duration("7d"), do: 604800
  defp parse_duration(_), do: 3600

  defp widget_uses_device?(widget, device_id) do
    Enum.any?(widget.queries, fn q -> q.device_id == device_id end)
  end

  defp append_metrics_to_series(nil, _metrics, _widget), do: []
  defp append_metrics_to_series(series, metrics, widget) do
    Enum.map(Enum.zip(series, widget.queries), fn {s, query} ->
      relevant =
        metrics
        |> Enum.filter(fn m -> m.path == query.path end)
        |> Enum.map(fn m -> %{time: m.time, value: m.value_float || 0.0} end)

      %{s | data: trim_series(s.data ++ relevant, 500)}
    end)
  end

  defp trim_series(data, max_points) when length(data) > max_points do
    Enum.drop(data, length(data) - max_points)
  end
  defp trim_series(data, _), do: data

  defp widget_width(%{position: %{w: w}}), do: w * 80
  defp widget_height(%{position: %{h: h}}), do: h * 60
end
```

## Performance Considerations

### Client-Side Bundle Size

The Vega stack adds ~200-500KB minified JavaScript. Mitigations:
- Load Vega libraries lazily (only when a dashboard page is visited)
- Use CDN for Vega libraries in production
- The bundle is cached by the browser after first load

### Update Throttling

For high-frequency metrics (>10 Hz from gNMI streams), throttle chart updates to human-perceptible rates:

```elixir
# In DashboardLive, debounce PubSub updates per widget
defp schedule_chart_update(socket, widget_id) do
  timer_key = {:chart_timer, widget_id}

  case Map.get(socket.assigns, timer_key) do
    nil ->
      ref = Process.send_after(self(), {:flush_chart, widget_id}, 500)
      assign(socket, timer_key, ref)

    _existing ->
      # Already scheduled, skip
      socket
  end
end
```

### Data Windowing

Limit chart data to prevent browser memory issues:
- Keep at most 500-1000 data points per series in the browser
- For longer ranges, use TimescaleDB continuous aggregates to pre-aggregate
- Trim old points when appending new ones

## Intelligent Query Routing

Based on the requested time range, route to the most efficient data source:

```elixir
defmodule SwitchTelemetry.Metrics.QueryRouter do
  @moduledoc """
  Routes metric queries to the most efficient data source:
  - Raw hypertable for short ranges (< 1 hour)
  - 5-minute continuous aggregate for medium ranges (1h - 24h)
  - 1-hour continuous aggregate for long ranges (> 24h)
  """

  def query(device_id, path, time_range) do
    duration_seconds = DateTime.diff(time_range.end, time_range.start)

    cond do
      duration_seconds <= 3600 ->
        # Last hour: query raw data, 10-second buckets
        query_raw(device_id, path, "10 seconds", time_range)

      duration_seconds <= 86400 ->
        # Last day: query 5-minute aggregate
        query_aggregate("metrics_5m", device_id, path, time_range)

      true ->
        # Longer: query 1-hour aggregate
        query_aggregate("metrics_1h", device_id, path, time_range)
    end
  end
end
```

This ensures dashboards remain fast regardless of the time window the user selects.
