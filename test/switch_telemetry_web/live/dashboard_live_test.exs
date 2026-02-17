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

    test "shows dashboard description", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{
          id: "dash_desc_test",
          name: "Desc Dashboard",
          description: "A detailed description"
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "A detailed description"
    end

    test "shows add widget button", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{
          id: "dash_add_wgt",
          name: "Add Widget Test"
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "Add Widget"
    end

    test "displays widget titles in show view", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_wgt_show", name: "Widget Show"})

      {:ok, _} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_show_title",
          title: "Network Traffic",
          chart_type: :line
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "Network Traffic"
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

    test "clicking export triggers push_event", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_exp_click", name: "Export Click"})

      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_exp_click",
          title: "Export Click Chart",
          chart_type: :line
        })

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Click export button should not crash
      view
      |> element("button[phx-click=export_widget][phx-value-id=#{widget.id}]")
      |> render_click()

      # View should still render correctly after export
      html = render(view)
      assert html =~ "Export Click Chart"
    end
  end

  describe "Show - PubSub and handle_info" do
    test "receives widget_saved message and updates dashboard", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_ws", name: "Widget Save Test"})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Update the dashboard name first
      {:ok, updated} = Dashboards.update_dashboard(dashboard, %{name: "Updated Name"})
      updated = Dashboards.get_dashboard!(updated.id)

      # Simulate widget_saved message
      send(view.pid, {:widget_saved, updated})

      html = render(view)
      assert html =~ "Updated Name"
    end

    test "receives time_range_changed message", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_trc", name: "Time Range Change"})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Simulate time_range_changed message
      send(view.pid, {:time_range_changed, %{"type" => "relative", "duration" => "5m"}})

      # View should still render correctly
      html = render(view)
      assert html =~ "Time Range Change"
    end

    test "receives gnmi_metrics PubSub message with widget queries", %{conn: conn} do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: "dev_dash_pubsub",
          hostname: "dash-pubsub-dev.lab",
          ip_address: "10.0.20.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_pubsub", name: "PubSub Test"})

      {:ok, _widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_pubsub",
          title: "PubSub Widget",
          chart_type: :line,
          queries: [
            %{"device_id" => device.id, "path" => "/interfaces/counters", "label" => "counters"}
          ]
        })

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Send metric via PubSub
      metric = %{
        time: DateTime.utc_now(),
        path: "/interfaces/counters",
        value_float: 99.5
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, [metric]}
      )

      # View should still render without error
      html = render(view)
      assert html =~ "PubSub Widget"
    end

    test "handles unknown messages gracefully", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_unknown_msg", name: "Unknown Msg Test"})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      send(view.pid, {:random_unknown_message, "foo"})

      html = render(view)
      assert html =~ "Unknown Msg Test"
    end

    test "delete_widget with non-existent widget_id is handled", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_del_nonexist", name: "Delete Nonexist"})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

      # Send delete_widget event for a widget that doesn't exist on this dashboard
      render_click(view, "delete_widget", %{"id" => "non_existent_widget_id"})

      html = render(view)
      assert html =~ "Delete Nonexist"
    end
  end

  describe "Show - dashboard editing" do
    test "edit action shows form", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_edit_show", name: "Edit Show Test"})

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}/edit")
      assert html =~ "Edit Dashboard"
      assert html =~ "Edit Show Test"
      assert html =~ "Layout"
      assert html =~ "Refresh interval"
      assert html =~ "Public"
    end

    test "dashboard update with invalid data shows form again", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_edit_invalid", name: "Invalid Edit"})

      {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}/edit")

      # Submit with empty name (required field)
      view
      |> form("form", %{"dashboard" => %{"name" => ""}})
      |> render_submit()

      # The form should be shown again (no redirect)
      html = render(view)
      assert html =~ "Edit Dashboard"
    end
  end

  describe "Show - widget display" do
    test "shows no widgets message when empty", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_no_wgts", name: "No Widgets"})

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "No widgets configured"
    end

    test "hides no widgets message when widgets exist", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_has_wgts", name: "Has Widgets"})

      {:ok, _} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_exists",
          title: "Existing Widget",
          chart_type: :bar
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      refute html =~ "No widgets configured"
      assert html =~ "Existing Widget"
    end

    test "shows dashboard without description when none set", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_no_desc", name: "No Description"})

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "No Description"
      # Should not render description paragraph
      refute html =~ "<p"
    end

    test "widget with position shows correct grid span", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_grid", name: "Grid Test"})

      {:ok, _widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_grid",
          title: "Wide Widget",
          chart_type: :area,
          position: %{"w" => 12, "h" => 4}
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "Wide Widget"
      assert html =~ "col-span-12"
    end

    test "widget with small position shows correct grid span", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_grid_sm", name: "Small Grid"})

      {:ok, _widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_grid_sm",
          title: "Small Widget",
          chart_type: :line,
          position: %{"w" => 4, "h" => 3}
        })

      {:ok, _view, html} = live(conn, ~p"/dashboards/#{dashboard.id}")
      assert html =~ "col-span-4"
    end
  end
end
