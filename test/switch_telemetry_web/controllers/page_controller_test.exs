defmodule SwitchTelemetryWeb.PageControllerTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  describe "GET /" do
    test "redirects authenticated user to /dashboards", %{conn: conn} do
      user = create_test_user()
      conn = conn |> log_in_user(user) |> get(~p"/")
      assert redirected_to(conn) == ~p"/dashboards"
    end

    test "redirects unauthenticated user to /users/log_in", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "returns 302 status", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.status == 302
    end
  end
end
