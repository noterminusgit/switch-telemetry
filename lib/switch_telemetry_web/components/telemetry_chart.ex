defmodule SwitchTelemetryWeb.Components.TelemetryChart do
  @moduledoc """
  Reusable LiveComponent wrapping VegaLite/Tucan for telemetry charts.

  Accepts series data and chart configuration, builds a VegaLite spec,
  and pushes it to the browser via the VegaLiteHook for client-side rendering.
  """
  use SwitchTelemetryWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:width, fn -> 480 end)
      |> assign_new(:height, fn -> 300 end)
      |> assign_new(:chart_type, fn -> :line end)
      |> assign_new(:series, fn -> [] end)

    socket = push_chart_spec(socket)
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="telemetry-chart bg-white rounded-lg shadow p-4">
      <h3 :if={assigns[:title]} class="text-sm font-medium text-gray-700 mb-2">
        {@title}
      </h3>
      <div
        id={"chart-#{@id}"}
        phx-hook="VegaLite"
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
      build_chart(data, chart_type, width, height)
    end
  end

  defp build_chart(data, chart_type, width, height) do
    mark = chart_type_to_mark(chart_type)

    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "width" => width,
      "height" => height,
      "data" => %{"values" => data},
      "mark" => %{"type" => mark, "tooltip" => true, "point" => mark == "line"},
      "encoding" => %{
        "x" => %{
          "field" => "time",
          "type" => "temporal",
          "axis" => %{"title" => "Time", "format" => "%H:%M:%S"}
        },
        "y" => %{
          "field" => "value",
          "type" => "quantitative",
          "axis" => %{"title" => "Value"}
        },
        "color" => %{
          "field" => "label",
          "type" => "nominal",
          "legend" => %{"title" => "Series"}
        }
      },
      "selection" => %{
        "brush" => %{"type" => "interval", "encodings" => ["x"]}
      }
    }
  end

  defp chart_type_to_mark(:line), do: "line"
  defp chart_type_to_mark(:area), do: "area"
  defp chart_type_to_mark(:bar), do: "bar"
  defp chart_type_to_mark(:points), do: "point"
  defp chart_type_to_mark(_), do: "line"

  defp flatten_series(series) do
    Enum.flat_map(series, fn s ->
      Enum.map(s.data, fn point ->
        %{
          "time" => format_time(point.time),
          "value" => point.value,
          "label" => s.label
        }
      end)
    end)
  end

  defp format_time(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_time(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_time(other), do: to_string(other)

  defp empty_spec(width, height) do
    %{
      "$schema" => "https://vega.github.io/schema/vega-lite/v5.json",
      "width" => width,
      "height" => height,
      "data" => %{"values" => []},
      "mark" => "text",
      "encoding" => %{},
      "title" => "No data available"
    }
  end
end
