defmodule SwitchTelemetryWeb.UserAuthTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  alias SwitchTelemetry.Accounts
  alias SwitchTelemetryWeb.UserAuth

  @endpoint SwitchTelemetryWeb.Endpoint

  setup do
    user = create_test_user()
    %{user: user}
  end

  # Helper to prepare a conn for direct plug testing (session + flash initialized)
  defp prepare_conn(conn) do
    conn
    |> init_test_session(%{})
    |> fetch_flash()
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> UserAuth.fetch_current_user([])
      assert conn.assigns.current_user.id == user.id
    end

    test "does not authenticate if no session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> UserAuth.fetch_current_user([])

      refute conn.assigns.current_user
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn =
        conn
        |> prepare_conn()
        |> UserAuth.fetch_current_user([])
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_user([])
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> UserAuth.fetch_current_user([])
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/dashboards"
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> UserAuth.fetch_current_user([])
        |> UserAuth.redirect_if_user_is_authenticated([])

      refute conn.halted
    end
  end

  describe "require_admin/2" do
    test "redirects if user is not admin", %{conn: conn} do
      viewer = create_test_user(%{role: :viewer})

      conn =
        conn
        |> log_in_user(viewer)
        |> fetch_flash()
        |> UserAuth.fetch_current_user([])
        |> UserAuth.require_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"
    end

    test "does not redirect if user is admin", %{conn: conn} do
      admin = create_test_user(%{role: :admin})

      conn =
        conn
        |> log_in_user(admin)
        |> UserAuth.fetch_current_user([])
        |> UserAuth.require_admin([])

      refute conn.halted
    end
  end

  describe "log_in_user/3 via HTTP" do
    test "stores the user token in the session on login", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "valid_password_123"}
        })

      assert token = get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboards"
      assert Accounts.get_user_by_session_token(token)
    end

    test "writes remember_me cookie on login", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => "valid_password_123",
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_switch_telemetry_web_user_remember_me"]
    end
  end

  describe "log_out_user/1 via HTTP" do
    test "erases session and cookies on logout", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")

      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies["_switch_telemetry_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
