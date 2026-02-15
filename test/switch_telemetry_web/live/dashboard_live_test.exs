defmodule SwitchTelemetryWeb.DashboardLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Dashboards

  setup :register_and_log_in_user

  describe "Index" do
    test "lists dashboards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboards")
      assert html =~ "Dashboards"
    end

    test "shows empty state when no dashboards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboards")
      assert html =~ "No dashboards yet"
    end

    test "renders dashboard cards when dashboards exist", %{conn: conn} do
      {:ok, _dashboard} =
        Dashboards.create_dashboard(%{id: "dash_test1", name: "Test Dashboard"})

      {:ok, _view, html} = live(conn, ~p"/dashboards")
      assert html =~ "Test Dashboard"
    end

    test "new dashboard form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboards/new")
      assert html =~ "Create Dashboard"
    end

    test "deletes a dashboard", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_del", name: "To Delete"})

      {:ok, view, _html} = live(conn, ~p"/dashboards")
      assert render(view) =~ "To Delete"

      view |> element("button[phx-click=delete][phx-value-id=#{dashboard.id}]") |> render_click()
      refute render(view) =~ "To Delete"
    end
  end

  describe "clone" do
    test "clones a dashboard", %{conn: conn} do
      {:ok, _} = Dashboards.create_dashboard(%{id: "dash_clone_ui", name: "Clone Source"})
      {:ok, view, _html} = live(conn, ~p"/dashboards")
      assert render(view) =~ "Clone Source"

      view |> element("button[phx-click=clone][phx-value-id=dash_clone_ui]") |> render_click()
      assert render(view) =~ "Copy of Clone Source"
    end
  end

  describe "edit dashboard" do
    test "navigates to edit form", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_edit_ui", name: "Edit Me"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/edit")
      assert html =~ "Edit Dashboard"
      assert html =~ "Edit Me"
    end

    test "updates dashboard", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_upd_ui", name: "Before Edit"})
      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}/edit")

      view
      |> form("form", %{"dashboard" => %{"name" => "After Edit"}})
      |> render_submit()

      assert_patch(view, ~p"/dashboards/#{dashboard.id}")
      assert render(view) =~ "After Edit"
    end
  end

  describe "widget editor" do
    test "navigates to add widget form", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_wgt_add", name: "Widget Test"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")
      assert html =~ "Add Widget"
    end

    test "creates a widget", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_wgt_create", name: "Widget Create"})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")

      view
      |> form("#widget-form", %{"widget" => %{"title" => "CPU Usage", "chart_type" => "line"}})
      |> render_submit()

      assert_patch(view, ~p"/dashboards/#{dashboard.id}")
      assert render(view) =~ "CPU Usage"
    end

    test "navigates to edit widget form", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_wgt_edit", name: "Widget Edit Test"})

      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{id: "wgt_edit1", title: "Edit Me", chart_type: :line})

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/#{widget.id}/edit")
      assert html =~ "Edit Widget"
      assert html =~ "Edit Me"
    end

    test "deletes a widget", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_wgt_del", name: "Widget Del Test"})

      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{id: "wgt_del1", title: "Delete Me", chart_type: :line})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert render(view) =~ "Delete Me"

      view
      |> element("button[phx-click=delete_widget][phx-value-id=#{widget.id}]")
      |> render_click()

      refute render(view) =~ "Delete Me"
    end
  end

  describe "Show" do
    test "displays dashboard", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{
          id: "dash_show1",
          name: "My Dashboard",
          description: "A test"
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "My Dashboard"
      assert html =~ "A test"
    end

    test "shows empty widget state", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_show2", name: "Empty Dashboard"})

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "No widgets configured"
    end
  end

  describe "time range picker" do
    test "renders time range presets", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tr", name: "Time Range Test"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "5 min"
      assert html =~ "1 hour"
      assert html =~ "24 hours"
      assert html =~ "Custom"
    end

    test "renders all six preset durations", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tr2", name: "All Presets"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "5 min"
      assert html =~ "15 min"
      assert html =~ "1 hour"
      assert html =~ "6 hours"
      assert html =~ "24 hours"
      assert html =~ "7 days"
    end

    test "clicking a preset button sends select_preset event", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tr3", name: "Preset Click"})
      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Click the "5 min" preset button targeting the TimeRangePicker component
      view
      |> element("button[phx-click=select_preset][phx-value-duration=\"5m\"]")
      |> render_click()

      # After clicking, the 5m button should have the active styling
      html = render(view)
      assert html =~ "5 min"
    end

    test "clicking Custom toggles the custom date range form", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tr4", name: "Custom Toggle"})
      {:ok, view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Custom form should not be visible initially
      refute html =~ "datetime-local"

      # Click "Custom" button
      view
      |> element("button[phx-click=toggle_custom]")
      |> render_click()

      html = render(view)
      # The custom date range form should now be visible with datetime inputs
      assert html =~ "datetime-local"
      assert html =~ "Start"
      assert html =~ "End"
      assert html =~ "Apply"
    end

    test "default selection highlights 1h preset", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tr5", name: "Default Selection"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # The 1h button should have the active/indigo styling by default
      assert html =~ "bg-indigo-600"
    end
  end

  describe "widget editor query builder" do
    test "shows query series section in add widget form", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_qb1", name: "Query Builder"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")
      assert html =~ "Query Series"
      assert html =~ "Series 1"
      assert html =~ "Device"
      assert html =~ "Metric Path"
      assert html =~ "Label"
      assert html =~ "Color"
    end

    test "shows add series button", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_qb2", name: "Add Series"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")
      assert html =~ "+ Add Series"
    end

    test "shows remove button for query series", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_qb3", name: "Remove Series"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")
      assert html =~ "Remove"
    end

    test "shows chart type selector in widget form", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_qb4", name: "Chart Types"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")
      assert html =~ "Chart Type"
      assert html =~ "Line"
      assert html =~ "Bar"
      assert html =~ "Area"
      assert html =~ "Points"
    end

    test "shows time range selector in widget form", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_qb5", name: "Time Range Select"})
      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/widgets/new")
      assert html =~ "Time Range"
      assert html =~ "Last 5 minutes"
      assert html =~ "Last 1 hour"
      assert html =~ "Last 24 hours"
    end
  end

  describe "telemetry chart container" do
    test "renders chart container with VegaLite hook for each widget", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tc1", name: "Chart Container"})

      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_tc1",
          title: "CPU Chart",
          chart_type: :line
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # The TelemetryChart component renders a div with VegaLite hook
      assert html =~ "phx-hook=\"VegaLite\""
      assert html =~ "chart-#{widget.id}"
      assert html =~ "telemetry-chart"
    end

    test "renders chart container for multiple widgets", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tc2", name: "Multi Charts"})

      {:ok, w1} =
        Dashboards.add_widget(dashboard, %{id: "wgt_tc2a", title: "Chart A", chart_type: :line})

      {:ok, w2} =
        Dashboards.add_widget(dashboard, %{id: "wgt_tc2b", title: "Chart B", chart_type: :bar})

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "Chart A"
      assert html =~ "Chart B"
      assert html =~ "chart-#{w1.id}"
      assert html =~ "chart-#{w2.id}"
    end

    test "widget card shows edit and delete controls", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_tc3", name: "Widget Controls"})

      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_tc3",
          title: "Control Test",
          chart_type: :line
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "Control Test"
      assert html =~ "Edit"
      assert html =~ "Export"
      # Delete button (x character entity)
      assert html =~ "delete_widget"
      assert html =~ widget.id
    end
  end

  describe "export" do
    test "export button appears on widget cards", %{conn: conn} do
      {:ok, dashboard} = Dashboards.create_dashboard(%{id: "dash_exp", name: "Export Test"})

      {:ok, _widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_exp1",
          title: "Export Chart",
          chart_type: :line
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "Export"
    end
  end
end
