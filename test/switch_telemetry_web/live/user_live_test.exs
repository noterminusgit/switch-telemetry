defmodule SwitchTelemetryWeb.UserLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Accounts

  describe "Index (admin user)" do
    setup %{conn: conn} do
      admin = create_test_user(%{role: :admin})
      conn = log_in_user(conn, admin)
      %{conn: conn, user: admin}
    end

    test "renders user management page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "User Management"
      assert html =~ "Manage user accounts and roles"
    end

    test "lists all users", %{conn: conn, user: admin} do
      other_user = create_test_user(%{role: :viewer})

      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ admin.email
      assert html =~ other_user.email
    end

    test "shows user roles", %{conn: conn} do
      _viewer = create_test_user(%{role: :viewer})
      _operator = create_test_user(%{role: :operator})

      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "admin"
      assert html =~ "viewer"
      assert html =~ "operator"
    end

    test "changes a user role", %{conn: conn} do
      viewer = create_test_user(%{role: :viewer})

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      view
      |> element(~s|form[phx-change="change_role"][phx-value-user-id="#{viewer.id}"]|)
      |> render_change(%{"role" => "operator"})

      html = render(view)
      assert html =~ "Role updated."

      updated = Accounts.get_user!(viewer.id)
      assert updated.role == :operator
    end

    test "deletes a user", %{conn: conn} do
      target =
        create_test_user(%{role: :viewer, user_attrs: %{email: "delete-target@example.com"}})

      {:ok, view, html} = live(conn, ~p"/admin/users")
      assert html =~ "delete-target@example.com"

      view
      |> element(~s|button[phx-click="delete_user"][phx-value-id="#{target.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "User deleted."
      refute html =~ "delete-target@example.com"
    end

    test "cannot delete yourself", %{conn: conn, user: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      # The delete button should not appear for the current user (guarded by :if)
      refute html =~
               ~s|phx-click="delete_user" phx-value-id="#{admin.id}"|
    end
  end

  describe "Index (non-admin user)" do
    setup %{conn: conn} do
      user = create_test_user(%{role: :operator})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "non-admin user is redirected", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/admin/users")

      assert path == "/"
      assert flash["error"] =~ "not authorized"
    end
  end

  describe "Settings" do
    setup %{conn: conn} do
      user = create_test_user()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "renders settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "Account Settings"
      assert html =~ "Manage your email address and password"
    end

    test "renders email change form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "Email"
      assert html =~ "Current password"
      assert html =~ "Change Email"
    end

    test "renders password change form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings")
      assert html =~ "New password"
      assert html =~ "Confirm new password"
      assert html =~ "Change Password"
    end

    test "validates email change form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> form("#email_form", %{
          "current_password" => "wrong",
          "user" => %{"email" => "notanemail"}
        })
        |> render_change()

      assert html =~ "must have the @ sign and no spaces"
    end

    test "validates password change form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> form("#password_form", %{
          "current_password" => "wrong",
          "user" => %{"password" => "short", "password_confirmation" => "nope"}
        })
        |> render_change()

      assert html =~ "should be at least"
    end

    test "updates email with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> form("#email_form", %{
        "current_password" => "valid_password_123",
        "user" => %{"email" => "newemail@example.com"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "A link to confirm your email change has been sent"
    end

    test "updates password with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> form("#password_form", %{
        "current_password" => "valid_password_123",
        "user" => %{
          "password" => "new_valid_password_456",
          "password_confirmation" => "new_valid_password_456"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/settings")
      assert flash["info"] == "Password updated successfully."
    end

    test "rejects email change with wrong password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      view
      |> form("#email_form", %{
        "current_password" => "wrong_password",
        "user" => %{"email" => "newemail@example.com"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ "is not valid"
    end

    test "rejects password change with wrong current password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")

      html =
        view
        |> form("#password_form", %{
          "current_password" => "wrong_password",
          "user" => %{
            "password" => "new_valid_password_456",
            "password_confirmation" => "new_valid_password_456"
          }
        })
        |> render_submit()

      assert html =~ "is not valid"
    end
  end
end
