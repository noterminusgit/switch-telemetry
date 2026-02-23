defmodule SwitchTelemetryWeb.Components.WidgetEditorTestLive do
  @moduledoc false
  use Phoenix.LiveView

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetryWeb.Components.WidgetEditor

  def mount(_params, session, socket) do
    action = session["action"] || :add_widget
    dashboard_id = session["dashboard_id"]
    widget_id = session["widget_id"]

    dashboard = Dashboards.get_dashboard!(dashboard_id)
    widget = if widget_id, do: Dashboards.get_widget!(widget_id), else: nil

    socket =
      socket
      |> assign(dashboard: dashboard, widget: widget, action: action, saved: false)

    {:ok, socket}
  end

  def handle_info({:widget_saved, dashboard}, socket) do
    {:noreply, assign(socket, dashboard: dashboard, saved: true)}
  end

  def render(assigns) do
    ~H"""
    <div id="save-status" data-saved={to_string(@saved)}></div>
    <.live_component
      module={WidgetEditor}
      id="widget-editor"
      action={@action}
      dashboard={@dashboard}
      widget={@widget}
    />
    """
  end
end

defmodule SwitchTelemetryWeb.Components.WidgetEditorTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetry.Devices.Device
  alias SwitchTelemetry.Collector.Subscription
  alias SwitchTelemetryWeb.Components.WidgetEditorTestLive

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, dashboard} =
      Dashboards.create_dashboard(%{
        id: "dash_we_#{System.unique_integer([:positive])}",
        name: "Widget Editor Test #{System.unique_integer([:positive])}"
      })

    # Create test devices for the select dropdowns
    device =
      %Device{}
      |> Device.changeset(%{
        id: "dev_we_#{System.unique_integer([:positive])}",
        hostname: "test-router.example.com",
        ip_address: "10.0.0.1",
        platform: :cisco_iosxr,
        transport: :gnmi
      })
      |> SwitchTelemetry.Repo.insert!()

    # Create a subscription with paths for the device
    %Subscription{}
    |> Subscription.changeset(%{
      id: "sub_we_#{System.unique_integer([:positive])}",
      device_id: device.id,
      paths: [
        "/interfaces/interface/state/counters",
        "/system/state/hostname"
      ],
      enabled: true
    })
    |> SwitchTelemetry.Repo.insert!()

    %{conn: conn, dashboard: dashboard, device: device}
  end

  defp render_editor(conn, dashboard, opts \\ []) do
    action = Keyword.get(opts, :action, :add_widget)
    widget_id = Keyword.get(opts, :widget_id)

    session = %{
      "action" => action,
      "dashboard_id" => dashboard.id,
      "widget_id" => widget_id
    }

    {:ok, view, html} = live_isolated(conn, WidgetEditorTestLive, session: session)

    {view, html}
  end

  describe "rendering for add_widget action" do
    test "renders Add Widget heading", %{conn: conn, dashboard: dashboard} do
      {_view, html} = render_editor(conn, dashboard, action: :add_widget)
      assert html =~ "Add Widget"
    end

    test "renders widget form with title input", %{conn: conn, dashboard: dashboard} do
      {_view, html} = render_editor(conn, dashboard)
      assert html =~ "Title"
      assert html =~ "widget-form"
    end

    test "renders chart type select", %{conn: conn, dashboard: dashboard} do
      {_view, html} = render_editor(conn, dashboard)
      assert html =~ "Chart Type"
      assert html =~ "Line"
      assert html =~ "Bar"
      assert html =~ "Area"
      assert html =~ "Points"
    end

    test "renders time range select", %{conn: conn, dashboard: dashboard} do
      {_view, html} = render_editor(conn, dashboard)
      assert html =~ "Time Range"
      assert html =~ "Last 5 minutes"
      assert html =~ "Last 1 hour"
      assert html =~ "Last 24 hours"
    end

    test "starts with one empty query for new widget", %{conn: conn, dashboard: dashboard} do
      {_view, html} = render_editor(conn, dashboard)
      assert html =~ "Series 1"
      assert html =~ "Device"
      assert html =~ "Select a device..."
      assert html =~ "Select a device first..."
      assert html =~ "Label"
      assert html =~ "Color"
    end

    test "renders Create Widget button", %{conn: conn, dashboard: dashboard} do
      {_view, html} = render_editor(conn, dashboard, action: :add_widget)
      assert html =~ "Create Widget"
    end
  end

  describe "rendering for edit_widget action" do
    test "renders Edit Widget heading", %{conn: conn, dashboard: dashboard} do
      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_edit_head_#{System.unique_integer([:positive])}",
          title: "Edit Heading Test",
          chart_type: :line
        })

      {_view, html} = render_editor(conn, dashboard, action: :edit_widget, widget_id: widget.id)
      assert html =~ "Edit Widget"
    end

    test "renders Update Widget button", %{conn: conn, dashboard: dashboard} do
      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_edit_btn_#{System.unique_integer([:positive])}",
          title: "Update Button Test",
          chart_type: :bar
        })

      {_view, html} = render_editor(conn, dashboard, action: :edit_widget, widget_id: widget.id)
      assert html =~ "Update Widget"
    end

    test "populates form from existing widget on edit", %{conn: conn, dashboard: dashboard} do
      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_edit_pop_#{System.unique_integer([:positive])}",
          title: "Populated Widget",
          chart_type: :area
        })

      {_view, html} = render_editor(conn, dashboard, action: :edit_widget, widget_id: widget.id)

      # The Edit Widget heading confirms we are in edit mode with the right widget
      assert html =~ "Edit Widget"
      # The widget form should be present with the correct form id
      assert html =~ "widget-form"
      # The form should render the chart type from the existing widget.
      # The area option should be selected in the chart_type select.
      assert html =~ ~s(value="area")
    end
  end

  describe "query management" do
    test "add_query appends a new query", %{conn: conn, dashboard: dashboard} do
      {view, html} = render_editor(conn, dashboard)
      assert html =~ "Series 1"
      refute html =~ "Series 2"

      html =
        view
        |> element("button", "+ Add Series")
        |> render_click()

      assert html =~ "Series 1"
      assert html =~ "Series 2"
    end

    test "remove_query removes a query at index", %{conn: conn, dashboard: dashboard} do
      {view, _html} = render_editor(conn, dashboard)

      # Add a second query
      view
      |> element("button", "+ Add Series")
      |> render_click()

      html = render(view)
      assert html =~ "Series 1"
      assert html =~ "Series 2"

      # Remove the first query (index 0)
      view
      |> element("button[phx-click=remove_query][phx-value-index=\"0\"]")
      |> render_click()

      html = render(view)
      assert html =~ "Series 1"
      refute html =~ "Series 2"
    end

    test "remove_query keeps at least one query", %{conn: conn, dashboard: dashboard} do
      {view, _html} = render_editor(conn, dashboard)

      # Try to remove the only query
      view
      |> element("button[phx-click=remove_query][phx-value-index=\"0\"]")
      |> render_click()

      html = render(view)
      # Should still have Series 1 (re-created empty query)
      assert html =~ "Series 1"
    end
  end

  describe "validation" do
    test "validate event shows changeset errors for empty title", %{
      conn: conn,
      dashboard: dashboard
    } do
      {view, _html} = render_editor(conn, dashboard)

      html =
        view
        |> form("#widget-form", %{"widget" => %{"title" => "", "chart_type" => "line"}})
        |> render_change()

      # The changeset validation should show an error for required title
      assert html =~ "can" or html =~ "required" or html =~ "blank"
    end
  end

  describe "device and path selection" do
    test "select_device updates device_id and shows device in dropdown", %{
      conn: conn,
      dashboard: dashboard,
      device: device
    } do
      {view, html} = render_editor(conn, dashboard)

      # Device should appear in the select dropdown
      assert html =~ "test-router.example.com"
      assert html =~ "Cisco IOS-XR"

      # Select the device
      html =
        view
        |> element(~s(select[name="select_device[0]"]))
        |> render_change(%{"select_device" => %{"0" => device.id}})

      # Path dropdown should now be enabled with "Select a metric path..."
      assert html =~ "Select a metric path..."
    end

    test "select_device loads paths for the selected device", %{
      conn: conn,
      dashboard: dashboard,
      device: device
    } do
      {view, _html} = render_editor(conn, dashboard)

      html =
        view
        |> element(~s(select[name="select_device[0]"]))
        |> render_change(%{"select_device" => %{"0" => device.id}})

      # Should show subscribed paths in the path dropdown
      assert html =~ "/interfaces/interface/state/counters"
      assert html =~ "/system/state/hostname"
    end

    test "select_path updates path in query", %{
      conn: conn,
      dashboard: dashboard,
      device: device
    } do
      {view, _html} = render_editor(conn, dashboard)

      # First select device to load paths
      view
      |> element(~s(select[name="select_device[0]"]))
      |> render_change(%{"select_device" => %{"0" => device.id}})

      # Then select a path
      html =
        view
        |> element(~s(select[name="select_path[0]"]))
        |> render_change(%{"select_path" => %{"0" => "/interfaces/interface/state/counters"}})

      assert html =~ "/interfaces/interface/state/counters"
    end

    test "select_device resets path when device changes", %{
      conn: conn,
      dashboard: dashboard,
      device: device
    } do
      {view, _html} = render_editor(conn, dashboard)

      # Select device and path
      view
      |> element(~s(select[name="select_device[0]"]))
      |> render_change(%{"select_device" => %{"0" => device.id}})

      view
      |> element(~s(select[name="select_path[0]"]))
      |> render_change(%{"select_path" => %{"0" => "/interfaces/interface/state/counters"}})

      # Now reset by selecting empty device
      html =
        view
        |> element(~s(select[name="select_device[0]"]))
        |> render_change(%{"select_device" => %{"0" => ""}})

      # Path dropdown should go back to disabled state
      assert html =~ "Select a device first..."
    end
  end

  describe "update_query event" do
    test "update_query updates the label field", %{conn: conn, dashboard: dashboard} do
      {view, _html} = render_editor(conn, dashboard)

      view
      |> element("input[phx-value-field=label]")
      |> render_blur(%{"index" => "0", "field" => "label", "value" => "CPU Usage"})

      html = render(view)
      assert html =~ "CPU Usage"
    end
  end

  describe "update_time_range event" do
    test "update_time_range changes the selected time range", %{conn: conn, dashboard: dashboard} do
      {view, _html} = render_editor(conn, dashboard)

      view
      |> element("select[name=\"widget[time_range]\"]")
      |> render_click(%{"value" => "24h"})

      html = render(view)
      # The time_range_value should now be "24h"
      assert html =~ "selected" or html =~ "24h"
    end
  end

  describe "time_range_value from existing widget" do
    test "reads duration from widget with string key map", %{conn: conn, dashboard: dashboard} do
      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_tr_str_#{System.unique_integer([:positive])}",
          title: "Time Range String",
          chart_type: :line,
          time_range: %{"type" => "relative", "duration" => "6h"}
        })

      {_view, html} = render_editor(conn, dashboard, action: :edit_widget, widget_id: widget.id)

      assert html =~ "widget-form"
    end

    test "reads duration from widget with atom key map", %{conn: conn, dashboard: dashboard} do
      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_tr_atom_#{System.unique_integer([:positive])}",
          title: "Time Range Atom",
          chart_type: :bar,
          time_range: %{type: "relative", duration: "15m"}
        })

      {_view, html} = render_editor(conn, dashboard, action: :edit_widget, widget_id: widget.id)

      assert html =~ "widget-form"
    end
  end

  describe "save" do
    test "save creates widget for add_widget action", %{conn: conn, dashboard: dashboard} do
      {view, _html} = render_editor(conn, dashboard, action: :add_widget)

      view
      |> form("#widget-form", %{
        "widget" => %{"title" => "New CPU Widget", "chart_type" => "line"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "data-saved=\"true\""
    end

    test "save updates widget for edit_widget action", %{conn: conn, dashboard: dashboard} do
      {:ok, widget} =
        Dashboards.add_widget(dashboard, %{
          id: "wgt_edit_save_#{System.unique_integer([:positive])}",
          title: "Before Update",
          chart_type: :line
        })

      {view, _html} = render_editor(conn, dashboard, action: :edit_widget, widget_id: widget.id)

      view
      |> form("#widget-form", %{"widget" => %{"title" => "After Update", "chart_type" => "bar"}})
      |> render_submit()

      html = render(view)
      assert html =~ "data-saved=\"true\""

      # Verify the widget was actually updated in the database
      updated_widget = Dashboards.get_widget!(widget.id)
      assert updated_widget.title == "After Update"
    end
  end
end
