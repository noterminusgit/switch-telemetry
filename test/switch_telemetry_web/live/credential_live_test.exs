defmodule SwitchTelemetryWeb.CredentialLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Devices

  setup :register_and_log_in_user

  defp create_credential(attrs) do
    defaults = %{
      "id" => "cred_#{System.unique_integer([:positive])}",
      "name" => "Test Credential #{System.unique_integer([:positive])}",
      "username" => "testuser"
    }

    {:ok, credential} = Devices.create_credential(Map.merge(defaults, attrs))
    credential
  end

  describe "Index" do
    test "lists credentials", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/credentials")
      assert html =~ "Credentials"
      assert html =~ "Manage device authentication credentials."
    end

    test "shows empty state when no credentials", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/credentials")
      assert html =~ "No credentials configured"
    end

    test "renders credential rows", %{conn: conn} do
      credential = create_credential(%{"name" => "Lab Switch Creds", "username" => "labadmin"})

      {:ok, _view, html} = live(conn, ~p"/credentials")
      assert html =~ "Lab Switch Creds"
      assert html =~ "labadmin"
      assert html =~ credential.id
    end

    test "shows auth type for password credentials", %{conn: conn} do
      _credential =
        create_credential(%{
          "name" => "Password Cred",
          "username" => "admin",
          "password" => "secret123"
        })

      {:ok, _view, html} = live(conn, ~p"/credentials")
      assert html =~ "Password"
    end

    test "deletes a credential", %{conn: conn} do
      credential = create_credential(%{"name" => "Delete Me Cred"})

      {:ok, view, html} = live(conn, ~p"/credentials")
      assert html =~ "Delete Me Cred"

      view
      |> element(~s|button[phx-click="delete"][phx-value-id="#{credential.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Credential deleted"
      refute html =~ "Delete Me Cred"
    end
  end

  describe "Index - New" do
    test "navigates to new credential form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/credentials/new")
      assert html =~ "Create Credential"
    end

    test "creates a credential via the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/credentials/new")

      view
      |> form("form", %{
        "credential" => %{
          "name" => "New Switch Cred",
          "username" => "switchadmin",
          "password" => "password123"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/credentials")
      assert flash["info"] == "Credential created"
    end

    test "validates the form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/credentials/new")

      html =
        view
        |> form("form", %{"credential" => %{"name" => "", "username" => ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end

  describe "Show" do
    test "displays credential details", %{conn: conn} do
      credential =
        create_credential(%{
          "name" => "Show Me Cred",
          "username" => "showuser",
          "password" => "secretpass"
        })

      {:ok, _view, html} = live(conn, ~p"/credentials/#{credential.id}")
      assert html =~ "Show Me Cred"
      assert html =~ "showuser"
      assert html =~ "Credential details and configuration."
      # Password should be masked
      assert html =~ "********"
    end

    test "shows not set for empty optional fields", %{conn: conn} do
      credential = create_credential(%{"name" => "Minimal Cred", "username" => "minuser"})

      {:ok, _view, html} = live(conn, ~p"/credentials/#{credential.id}")
      assert html =~ "Not set"
    end

    test "has edit link", %{conn: conn} do
      credential = create_credential(%{"name" => "Edit Link Cred", "username" => "edituser"})

      {:ok, _view, html} = live(conn, ~p"/credentials/#{credential.id}")
      assert html =~ ~p"/credentials/#{credential.id}/edit"
    end
  end

  describe "Edit" do
    test "renders edit form", %{conn: conn} do
      credential = create_credential(%{"name" => "Edit Me Cred", "username" => "editme"})

      {:ok, _view, html} = live(conn, ~p"/credentials/#{credential.id}/edit")
      assert html =~ "Edit Credential"
      assert html =~ "Edit Me Cred"
    end

    test "updates a credential", %{conn: conn} do
      credential = create_credential(%{"name" => "Before Update", "username" => "beforeuser"})

      {:ok, view, _html} = live(conn, ~p"/credentials/#{credential.id}/edit")

      view
      |> form("form", %{
        "credential" => %{"name" => "After Update", "username" => "afteruser"}
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/credentials/#{credential.id}")
      assert flash["info"] == "Credential updated successfully"
    end

    test "validates on change", %{conn: conn} do
      credential = create_credential(%{"name" => "Validate Cred", "username" => "valuser"})

      {:ok, view, _html} = live(conn, ~p"/credentials/#{credential.id}/edit")

      html =
        view
        |> form("form", %{"credential" => %{"name" => ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end
  end
end
