defmodule SwitchTelemetryWeb.AdminEmailLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Accounts

  describe "Index (admin user)" do
    setup %{conn: conn} do
      user = create_test_user(%{role: :admin})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "renders admin email allowlist page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/admin_emails")
      assert html =~ "Admin Email Allowlist"
      assert html =~ "Manage which emails get automatic admin access"
      assert html =~ "Add Email"
    end

    test "shows empty state when no admin emails", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/admin_emails")
      assert html =~ "No emails on the allowlist yet."
    end

    test "lists existing admin emails", %{conn: conn} do
      {:ok, _} = Accounts.create_admin_email(%{"email" => "admin1@example.com"})
      {:ok, _} = Accounts.create_admin_email(%{"email" => "admin2@example.com"})

      {:ok, _view, html} = live(conn, ~p"/admin/admin_emails")
      assert html =~ "admin1@example.com"
      assert html =~ "admin2@example.com"
    end

    test "navigates to new admin email form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/admin_emails/new")
      assert html =~ "Add Admin Email"
    end

    test "creates a new admin email via the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/admin_emails/new")

      view
      |> form("#admin-email-form", %{"admin_email" => %{"email" => "new-admin@example.com"}})
      |> render_submit()

      assert_patch(view, ~p"/admin/admin_emails")
      html = render(view)
      assert html =~ "Admin email added."
      assert html =~ "new-admin@example.com"
    end

    test "validates admin email form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/admin_emails/new")

      html =
        view
        |> form("#admin-email-form", %{"admin_email" => %{"email" => ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "deletes an admin email", %{conn: conn} do
      {:ok, admin_email} = Accounts.create_admin_email(%{"email" => "delete-me@example.com"})

      {:ok, view, html} = live(conn, ~p"/admin/admin_emails")
      assert html =~ "delete-me@example.com"

      view
      |> element(~s|button[phx-click="delete"][phx-value-id="#{admin_email.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Admin email removed."
      refute html =~ "delete-me@example.com"
    end
  end

  describe "Index (non-admin user)" do
    setup %{conn: conn} do
      user = create_test_user(%{role: :viewer})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "non-admin user is redirected", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/admin/admin_emails")

      assert path == "/"
      assert flash["error"] =~ "not authorized"
    end
  end

  describe "Index (unauthenticated)" do
    test "unauthenticated user is redirected to login", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/admin_emails")
      assert path =~ "/users/log_in"
    end
  end
end
