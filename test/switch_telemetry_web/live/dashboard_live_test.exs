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
