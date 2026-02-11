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

      view |> element("button[phx-value-id=#{dashboard.id}]") |> render_click()
      refute render(view) =~ "To Delete"
    end
  end

  describe "Show" do
    test "displays dashboard", %{conn: conn} do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_show1", name: "My Dashboard", description: "A test"})

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
end
