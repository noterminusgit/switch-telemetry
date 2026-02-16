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

  describe "POST /users/log_in with remember_me" do
    test "sets remember_me cookie when remember_me is true", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => "valid_password_123",
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_switch_telemetry_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboards"
    end

    test "does not set remember_me cookie when remember_me is not set", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => "valid_password_123"
          }
        })

      refute conn.resp_cookies["_switch_telemetry_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/dashboards"
    end
  end

  describe "POST /users/log_in redirect when already authenticated" do
    test "redirects to dashboards when already logged in", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/log_in")

      assert redirected_to(conn) == ~p"/dashboards"
    end

    test "POST /users/log_in redirects if already authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "valid_password_123"}
        })

      assert redirected_to(conn) == ~p"/dashboards"
    end
  end

  describe "POST /users/magic_link" do
    test "sends magic link email for existing user", %{conn: conn} do
      # Create the user and add their email to the admin allowlist
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "magic-test@example.com",
          password: "valid_password_123"
        })

      # Add email to admin allowlist so admin_email? returns true
      SwitchTelemetry.Repo.insert!(%SwitchTelemetry.Accounts.AdminEmail{
        email: user.email
      })

      conn =
        post(conn, ~p"/users/magic_link", %{
          "magic_link" => %{"email" => "magic-test@example.com"}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      flash_info = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash_info =~ "admin allowlist"
    end

    test "shows same message for unknown email to prevent enumeration", %{conn: conn} do
      conn =
        post(conn, ~p"/users/magic_link", %{
          "magic_link" => %{"email" => "nonexistent@example.com"}
        })

      # Should still redirect with success-style message to prevent user enumeration
      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "admin allowlist"
    end

    test "shows same message for non-admin email to prevent enumeration", %{conn: conn} do
      {:ok, _user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "non-admin@example.com",
          password: "valid_password_123"
        })

      # Email exists but is not on the admin allowlist
      conn =
        post(conn, ~p"/users/magic_link", %{
          "magic_link" => %{"email" => "non-admin@example.com"}
        })

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "admin allowlist"
    end
  end

  describe "GET /users/magic_link/:token (magic_link_callback)" do
    test "redirects to login with error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/magic_link/invalid-token-here")
      assert redirected_to(conn) == ~p"/users/log_in"
      flash_error = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash_error =~ "invalid" or flash_error =~ "expired"
    end

    test "logs in user with valid magic link token", %{conn: conn} do
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "magic-valid@example.com",
          password: "valid_password_123"
        })

      # Generate a real magic link token
      {encoded_token, user_token} =
        SwitchTelemetry.Accounts.UserToken.build_email_token(user, "magic_link")

      SwitchTelemetry.Repo.insert!(user_token)

      conn = get(conn, ~p"/users/magic_link/#{encoded_token}")
      assert redirected_to(conn) == ~p"/dashboards"
      assert get_session(conn, :user_token)
    end

    test "magic link token is single-use", %{conn: conn} do
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "magic-single@example.com",
          password: "valid_password_123"
        })

      {encoded_token, user_token} =
        SwitchTelemetry.Accounts.UserToken.build_email_token(user, "magic_link")

      SwitchTelemetry.Repo.insert!(user_token)

      # First use should succeed
      conn1 = get(conn, ~p"/users/magic_link/#{encoded_token}")
      assert redirected_to(conn1) == ~p"/dashboards"

      # Second use should fail (token was deleted)
      conn2 = build_conn() |> get(~p"/users/magic_link/#{encoded_token}")
      assert redirected_to(conn2) == ~p"/users/log_in"
      flash_error = Phoenix.Flash.get(conn2.assigns.flash, :error)
      assert flash_error =~ "invalid" or flash_error =~ "expired"
    end
  end

  describe "admin promotion on login" do
    test "promotes user to admin on login if email is on admin allowlist", %{conn: conn} do
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "promote-me@example.com",
          password: "valid_password_123"
        })

      # Ensure user starts as non-admin
      assert user.role != :admin

      # Add to admin allowlist
      SwitchTelemetry.Repo.insert!(%SwitchTelemetry.Accounts.AdminEmail{
        email: "promote-me@example.com"
      })

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "promote-me@example.com", "password" => "valid_password_123"}
        })

      assert redirected_to(conn) == ~p"/dashboards"

      # Verify user was promoted
      updated_user = SwitchTelemetry.Accounts.get_user!(user.id)
      assert updated_user.role == :admin
    end

    test "does not promote user when email is not on admin allowlist", %{conn: conn} do
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "no-promote@example.com",
          password: "valid_password_123"
        })

      assert user.role != :admin

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => "no-promote@example.com", "password" => "valid_password_123"}
        })

      assert redirected_to(conn) == ~p"/dashboards"

      # Verify user was NOT promoted
      updated_user = SwitchTelemetry.Accounts.get_user!(user.id)
      assert updated_user.role != :admin
    end

    test "promotes user to admin on magic link callback if email is on admin allowlist", %{conn: conn} do
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "magic-promote@example.com",
          password: "valid_password_123"
        })

      assert user.role != :admin

      SwitchTelemetry.Repo.insert!(%SwitchTelemetry.Accounts.AdminEmail{
        email: "magic-promote@example.com"
      })

      {encoded_token, user_token} =
        SwitchTelemetry.Accounts.UserToken.build_email_token(user, "magic_link")

      SwitchTelemetry.Repo.insert!(user_token)

      conn = get(conn, ~p"/users/magic_link/#{encoded_token}")
      assert redirected_to(conn) == ~p"/dashboards"

      updated_user = SwitchTelemetry.Accounts.get_user!(user.id)
      assert updated_user.role == :admin
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/users/log_in"
      refute get_session(conn, :user_token)
    end

    test "shows flash message on logout", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out"
    end

    test "redirects to login page if user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
