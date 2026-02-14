defmodule SwitchTelemetryWeb.UserSessionControllerTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  setup do
    user = create_test_user()
    %{user: user}
  end

  describe "GET /users/log_in" do
    test "renders login page", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")
      response = html_response(conn, 200)
      assert response =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> get(~p"/users/log_in")
      assert redirected_to(conn) == ~p"/dashboards"
    end
  end

  describe "POST /users/log_in" do
    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "valid_password_123"}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboards"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
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

    test "returns error with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "wrong@example.com", "password" => "bad"}
        })

      response = html_response(conn, 200)
      assert response =~ "Invalid email or password"
    end

    test "logs the user in with flat params (browser form)", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "email" => user.email,
          "password" => "valid_password_123"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/dashboards"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_token)
    end
  end
end
