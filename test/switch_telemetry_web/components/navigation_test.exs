defmodule SwitchTelemetryWeb.Components.NavigationTest do
  use SwitchTelemetryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SwitchTelemetryWeb.Components.Sidebar
  import SwitchTelemetryWeb.Components.TopBar
  import SwitchTelemetryWeb.Components.MobileNav

  defp admin_user, do: %{email: "admin@example.com", role: :admin}
  defp viewer_user, do: %{email: "viewer@example.com", role: :viewer}

  describe "Sidebar" do
    test "renders all standard nav items" do
      html = render_component(&sidebar/1, %{current_user: viewer_user(), current_path: "/"})

      assert html =~ "Dashboards"
      assert html =~ "Devices"
      assert html =~ "Streams"
      assert html =~ "Alerts"
      assert html =~ "Credentials"
      assert html =~ "Settings"
    end

    test "renders app title" do
      html = render_component(&sidebar/1, %{current_user: viewer_user(), current_path: "/"})

      assert html =~ "Switch Telemetry"
    end

    test "highlights active nav item with aria-current" do
      html =
        render_component(&sidebar/1, %{current_user: viewer_user(), current_path: "/dashboards"})

      # The active link should have aria-current="page"
      assert html =~ ~s(aria-current="page")
    end

    test "highlights nested paths as active" do
      html =
        render_component(&sidebar/1, %{
          current_user: viewer_user(),
          current_path: "/dashboards/123"
        })

      assert html =~ ~s(aria-current="page")
    end

    test "does not highlight non-matching paths" do
      html =
        render_component(&sidebar/1, %{current_user: viewer_user(), current_path: "/devices"})

      # Parse out the dashboards link - it should NOT have aria-current
      # Devices should have aria-current
      assert html =~ ~s(aria-current="page")

      # Only one nav item should be active (Devices)
      # Check that Devices link area has aria-current
      [dashboards_section | _] = String.split(html, "Dashboards")
      refute dashboards_section =~ ~s(aria-current="page")
    end

    test "hides admin items for non-admin users" do
      html = render_component(&sidebar/1, %{current_user: viewer_user(), current_path: "/"})

      refute html =~ "Users"
    end

    test "shows admin items for admin users" do
      html = render_component(&sidebar/1, %{current_user: admin_user(), current_path: "/"})

      assert html =~ "Users"
    end
  end

  describe "TopBar" do
    test "renders user email when current_user is present" do
      html = render_component(&top_bar/1, %{current_user: admin_user()})

      assert html =~ "admin@example.com"
    end

    test "renders Log out link when current_user is present" do
      html = render_component(&top_bar/1, %{current_user: admin_user()})

      assert html =~ "Log out"
    end

    test "renders Log in link when current_user is nil" do
      html = render_component(&top_bar/1, %{current_user: nil})

      assert html =~ "Log in"
      refute html =~ "Log out"
    end

    test "renders hamburger button with Open sidebar text" do
      html = render_component(&top_bar/1, %{current_user: nil})

      assert html =~ "Open sidebar"
    end
  end

  describe "MobileNav" do
    test "renders all standard nav items" do
      html =
        render_component(&mobile_nav/1, %{current_user: viewer_user(), current_path: "/"})

      assert html =~ "Dashboards"
      assert html =~ "Devices"
      assert html =~ "Streams"
      assert html =~ "Alerts"
      assert html =~ "Credentials"
      assert html =~ "Settings"
    end

    test "hides admin items for non-admin users" do
      html =
        render_component(&mobile_nav/1, %{current_user: viewer_user(), current_path: "/"})

      refute html =~ "Users"
    end

    test "shows admin items for admin users" do
      html =
        render_component(&mobile_nav/1, %{current_user: admin_user(), current_path: "/"})

      assert html =~ "Users"
    end

    test "renders app title" do
      html =
        render_component(&mobile_nav/1, %{current_user: viewer_user(), current_path: "/"})

      assert html =~ "Switch Telemetry"
    end

    test "show_mobile_nav/1 returns a JS struct" do
      result = show_mobile_nav("mobile-nav")

      assert %Phoenix.LiveView.JS{} = result
    end

    test "hide_mobile_nav/1 returns a JS struct" do
      result = hide_mobile_nav("mobile-nav")

      assert %Phoenix.LiveView.JS{} = result
    end
  end
end
