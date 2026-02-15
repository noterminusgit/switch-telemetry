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
end
