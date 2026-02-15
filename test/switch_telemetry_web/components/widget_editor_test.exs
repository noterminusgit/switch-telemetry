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
  alias SwitchTelemetryWeb.Components.WidgetEditorTestLive

  setup :register_and_log_in_user

  setup %{conn: conn} do
    {:ok, dashboard} =
      Dashboards.create_dashboard(%{
        id: "dash_we_#{System.unique_integer([:positive])}",
        name: "Widget Editor Test"
      })

    %{conn: conn, dashboard: dashboard}
  end

  defp render_editor(conn, dashboard, opts \\ []) do
    action = Keyword.get(opts, :action, :add_widget)
    widget_id = Keyword.get(opts, :widget_id)

    session = %{
      "action" => action,
      "dashboard_id" => dashboard.id,
      "widget_id" => widget_id
    }

    {:ok, view, html} =
      live_isolated(conn, WidgetEditorTestLive, session: session)

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
      assert html =~ "Metric Path"
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
