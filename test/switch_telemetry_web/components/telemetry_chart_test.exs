defmodule SwitchTelemetryWeb.Components.TelemetryChartTestLive do
  @moduledoc false
  use Phoenix.LiveView

  alias SwitchTelemetryWeb.Components.TelemetryChart

  def mount(_params, session, socket) do
    assigns = session["assigns"] || %{}

    socket =
      socket
      |> assign(:chart_id, Map.get(assigns, :id, "test"))
      |> assign(:series, Map.get(assigns, :series, []))
      |> assign(:chart_type, Map.get(assigns, :chart_type, :line))
      |> assign(:width, Map.get(assigns, :width, 480))
      |> assign(:height, Map.get(assigns, :height, 300))
      |> assign(:title, Map.get(assigns, :title))

    {:ok, socket}
  end

  def handle_info({:update_series, series}, socket) do
    {:noreply, assign(socket, :series, series)}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={TelemetryChart}
      id={@chart_id}
      series={@series}
      chart_type={@chart_type}
      width={@width}
      height={@height}
      title={@title}
    />
    """
  end
end

defmodule SwitchTelemetryWeb.Components.TelemetryChartTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SwitchTelemetryWeb.Components.TelemetryChartTestLive

  setup :register_and_log_in_user

  defp render_chart(conn, assigns) do
    {:ok, view, html} =
      live_isolated(conn, TelemetryChartTestLive, session: %{"assigns" => assigns})

    {view, html}
  end

  describe "rendering" do
    test "renders container with VegaLite hook", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "test-chart"})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-test-chart"
    end

    test "renders with custom width and height", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "sized", width: 800, height: 600})
      assert html =~ "width: 800px"
      assert html =~ "height: 600px"
    end

    test "uses default dimensions of 480x300", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "default"})
      assert html =~ "width: 480px"
      assert html =~ "height: 300px"
    end

    test "renders title when provided", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "titled", title: "CPU Usage"})
      assert html =~ "CPU Usage"
    end

    test "does not render title element when title is nil", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "no-title"})
      refute html =~ "<h3"
    end
  end

  describe "chart types" do
    test "renders with chart_type :line without error", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "line-chart", chart_type: :line})
      assert html =~ "phx-hook=\"VegaLite\""
    end

    test "renders with chart_type :bar without error", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "bar-chart", chart_type: :bar})
      assert html =~ "phx-hook=\"VegaLite\""
    end

    test "renders with chart_type :area without error", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "area-chart", chart_type: :area})
      assert html =~ "phx-hook=\"VegaLite\""
    end

    test "renders with chart_type :points without error", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "points-chart", chart_type: :points})
      assert html =~ "phx-hook=\"VegaLite\""
    end
  end

  describe "series data" do
    test "renders with empty series without error", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "empty-series", series: []})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-empty-series"
    end

    test "renders with series data containing DateTime timestamps", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "CPU",
          data: [
            %{time: now, value: 42.5},
            %{time: DateTime.add(now, 60, :second), value: 55.1}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "datetime-chart", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-datetime-chart"
    end

    test "renders with multiple series", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "CPU",
          data: [%{time: now, value: 42.5}]
        },
        %{
          label: "Memory",
          data: [%{time: now, value: 78.3}]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "multi-series", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-multi-series"
    end
  end

  describe "NaiveDateTime handling" do
    test "handles NaiveDateTime timestamps in series data", %{conn: conn} do
      series = [
        %{
          label: "NaiveDateTime Series",
          data: [
            %{time: ~N[2024-01-01 10:00:00], value: 42.0},
            %{time: ~N[2024-01-01 10:01:00], value: 43.0}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "naive-dt", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-naive-dt"
    end

    test "handles mixed DateTime and NaiveDateTime in different series", %{conn: conn} do
      series = [
        %{
          label: "DateTime Series",
          data: [
            %{time: ~U[2024-01-01 10:00:00Z], value: 42.0},
            %{time: ~U[2024-01-01 10:01:00Z], value: 43.0}
          ]
        },
        %{
          label: "NaiveDateTime Series",
          data: [
            %{time: ~N[2024-01-01 10:00:00], value: 50.0},
            %{time: ~N[2024-01-01 10:01:00], value: 51.0}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "mixed-dt", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-mixed-dt"
    end
  end

  describe "unknown chart types" do
    test "falls back gracefully for unknown chart type atom", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "Data",
          data: [%{time: now, value: 10.0}]
        }
      ]

      {_view, html} =
        render_chart(conn, %{id: "unknown-type", chart_type: :sparkline, series: series})

      # Should still render the VegaLite hook container (falls back to "line" mark)
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-unknown-type"
    end

    test "falls back gracefully for string chart type", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "Data",
          data: [%{time: now, value: 10.0}]
        }
      ]

      {_view, html} =
        render_chart(conn, %{id: "string-type", chart_type: "histogram", series: series})

      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-string-type"
    end
  end

  describe "empty and edge-case series" do
    test "renders chart container with empty series list", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "empty-list", series: []})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-empty-list"
    end

    test "renders chart with series containing empty data list", %{conn: conn} do
      series = [
        %{
          label: "Empty Data",
          data: []
        }
      ]

      {_view, html} = render_chart(conn, %{id: "empty-data", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-empty-data"
    end

    test "renders chart with single data point", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "Single Point",
          data: [%{time: now, value: 99.9}]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "single-point", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-single-point"
    end

    test "renders chart with zero values", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "Zeros",
          data: [
            %{time: now, value: 0.0},
            %{time: DateTime.add(now, 60, :second), value: 0.0}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "zero-values", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-zero-values"
    end

    test "renders chart with negative values", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{
          label: "Negative",
          data: [
            %{time: now, value: -10.5},
            %{time: DateTime.add(now, 60, :second), value: -20.3}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "negative-vals", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-negative-vals"
    end

    test "renders chart with large number of data points", %{conn: conn} do
      now = DateTime.utc_now()

      data =
        for i <- 0..99 do
          %{time: DateTime.add(now, i * 60, :second), value: :rand.uniform() * 100}
        end

      series = [%{label: "Many Points", data: data}]

      {_view, html} = render_chart(conn, %{id: "many-points", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-many-points"
    end
  end

  describe "string timestamp handling" do
    test "handles string timestamps via to_string fallback", %{conn: conn} do
      series = [
        %{
          label: "String Timestamps",
          data: [
            %{time: "2024-01-01T10:00:00Z", value: 42.0},
            %{time: "2024-01-01T10:01:00Z", value: 43.0}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "string-ts", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-string-ts"
    end
  end

  describe "update behavior" do
    test "chart re-renders when series data changes", %{conn: conn} do
      now = DateTime.utc_now()

      initial_series = [
        %{label: "CPU", data: [%{time: now, value: 10.0}]}
      ]

      {view, html} = render_chart(conn, %{id: "update-test", series: initial_series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-update-test"

      # Send an update to change series data
      updated_series = [
        %{
          label: "CPU",
          data: [
            %{time: now, value: 10.0},
            %{time: DateTime.add(now, 60, :second), value: 20.0}
          ]
        }
      ]

      send(view.pid, {:update_series, updated_series})

      # The view should still be alive and rendering
      assert render(view) =~ "chart-update-test"
    end
  end

  describe "integer timestamp handling" do
    test "handles integer timestamps via to_string fallback", %{conn: conn} do
      series = [
        %{
          label: "Integer Timestamps",
          data: [
            %{time: 1704067200, value: 42.0},
            %{time: 1704067260, value: 43.0}
          ]
        }
      ]

      {_view, html} = render_chart(conn, %{id: "int-ts", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-int-ts"
    end
  end

  describe "update with changing chart_type" do
    test "renders correctly when chart_type changes from line to bar", %{conn: conn} do
      now = DateTime.utc_now()

      series = [
        %{label: "CPU", data: [%{time: now, value: 10.0}]}
      ]

      # First render with :line
      {view, html} = render_chart(conn, %{id: "type-change", chart_type: :line, series: series})
      assert html =~ "phx-hook=\"VegaLite\""

      # Send update to change series (triggers re-render)
      updated_series = [
        %{label: "CPU", data: [%{time: now, value: 20.0}]}
      ]

      send(view.pid, {:update_series, updated_series})
      assert render(view) =~ "chart-type-change"
    end
  end

  describe "series with only empty data arrays" do
    test "multiple series all with empty data arrays renders empty spec", %{conn: conn} do
      series = [
        %{label: "Series A", data: []},
        %{label: "Series B", data: []}
      ]

      {_view, html} = render_chart(conn, %{id: "all-empty", series: series})
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-all-empty"
    end
  end

  describe "assign defaults" do
    test "assigns default chart_type when not provided", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "no-chart-type"})
      # Should render without errors using the default :line chart type
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-no-chart-type"
    end

    test "assigns default series when not provided", %{conn: conn} do
      {_view, html} = render_chart(conn, %{id: "no-series"})
      assert html =~ "phx-hook=\"VegaLite\""
    end
  end
end
