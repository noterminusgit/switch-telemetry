defmodule SwitchTelemetryWeb.SubscriptionLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.{Collector, Devices}

  setup :register_and_log_in_user

  defp create_device do
    {:ok, device} =
      Devices.create_device(%{
        id: "dev_sub_#{System.unique_integer([:positive])}",
        hostname: "sw-test-sub.lab",
        ip_address: "10.0.0.#{:rand.uniform(254)}",
        platform: :cisco_iosxr,
        transport: :gnmi
      })

    device
  end

  defp create_subscription(device, attrs \\ %{}) do
    defaults = %{
      "id" => "sub_#{System.unique_integer([:positive])}",
      "device_id" => device.id,
      "paths" => ["/interfaces/interface/state/counters"],
      "mode" => "stream",
      "sample_interval_ns" => 30_000_000_000,
      "encoding" => "proto",
      "enabled" => true
    }

    {:ok, subscription} = Collector.create_subscription(Map.merge(defaults, attrs))
    subscription
  end

  describe "Index" do
    test "renders subscriptions page for device", %{conn: conn} do
      device = create_device()

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "Subscriptions"
      assert html =~ device.hostname
      assert html =~ device.ip_address
    end

    test "shows empty state when no subscriptions", %{conn: conn} do
      device = create_device()

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "No subscriptions configured for this device."
    end

    test "lists subscriptions for device", %{conn: conn} do
      device = create_device()

      _sub =
        create_subscription(device, %{
          "paths" => ["/interfaces/interface/state/counters"]
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "/interfaces/interface/state/counters"
      assert html =~ "stream"
      assert html =~ "proto"
      assert html =~ "Enabled"
    end

    test "shows interval formatted as seconds", %{conn: conn} do
      device = create_device()
      _sub = create_subscription(device, %{"sample_interval_ns" => 30_000_000_000})

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "30s"
    end

    test "shows interval formatted as minutes", %{conn: conn} do
      device = create_device()
      _sub = create_subscription(device, %{"sample_interval_ns" => 60_000_000_000})

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "1m"
    end

    test "toggles subscription enabled state", %{conn: conn} do
      device = create_device()
      sub = create_subscription(device, %{"enabled" => true})

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions")

      view
      |> element(~s|button[phx-click="toggle"][phx-value-id="#{sub.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Disabled"
    end

    test "deletes a subscription", %{conn: conn} do
      device = create_device()

      sub =
        create_subscription(device, %{
          "paths" => ["/system/state/hostname"]
        })

      {:ok, view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "/system/state/hostname"

      view
      |> element(~s|button[phx-click="delete"][phx-value-id="#{sub.id}"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Subscription deleted"
      refute html =~ "/system/state/hostname"
    end

    test "shows +N more when subscription has more than 3 paths", %{conn: conn} do
      device = create_device()

      _sub =
        create_subscription(device, %{
          "paths" => [
            "/interfaces/interface/state/counters",
            "/system/state/hostname",
            "/components/component/state",
            "/lldp/interfaces/interface/neighbors/neighbor/state"
          ]
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "+1 more"
    end

    test "handles subscription with nil interval gracefully", %{conn: conn} do
      device = create_device()

      _sub =
        create_subscription(device, %{
          "paths" => ["/interfaces/interface/state/counters"],
          "sample_interval_ns" => nil
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions")
      assert html =~ "-"
    end
  end

  describe "Index - New Subscription" do
    test "navigates to new subscription form with checkbox path list", %{conn: conn} do
      device = create_device()

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")
      assert html =~ "New Subscription"
      assert html =~ "Subscription Paths"
    end

    test "new subscription form shows Sample Interval (seconds) label", %{conn: conn} do
      device = create_device()
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")
      assert html =~ "Sample Interval (seconds)"
      refute html =~ "Sample Interval (nanoseconds)"
    end

    test "new subscription form defaults to 30 seconds", %{conn: conn} do
      device = create_device()
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")
      # Default sample_interval_ns is 30_000_000_000 ns = 30 seconds
      assert html =~ ~s(value="30")
    end

    test "shows available paths as checkboxes", %{conn: conn} do
      device = create_device()
      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")
      assert html =~ "/interfaces/interface/state/counters"
      assert html =~ "/system/state/hostname"
      assert html =~ "checkbox"
    end

    test "toggling a path checkbox selects it", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      html = render(view)
      assert html =~ "1 selected"
    end

    test "filter narrows visible paths", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      html =
        view
        |> element(~s|input[name="path_filter"]|)
        |> render_change(%{"path_filter" => "bgp"})

      assert html =~ "bgp"
      refute html =~ "/interfaces/interface/state/counters"
    end

    test "select all selects visible paths", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      view
      |> element(~s|button[phx-click="select_all_visible"]|)
      |> render_click()

      html = render(view)
      assert html =~ "selected"
    end

    test "deselect all clears selections", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Select all first
      view
      |> element(~s|button[phx-click="select_all_visible"]|)
      |> render_click()

      # Deselect all
      view
      |> element(~s|button[phx-click="deselect_all_visible"]|)
      |> render_click()

      html = render(view)
      assert html =~ "0 selected"
    end

    test "creates a subscription by selecting paths via checkboxes", %{conn: conn} do
      device = create_device()

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Select paths via checkboxes
      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/system/state/hostname"]|)
      |> render_click()

      # Submit the form
      view
      |> form("form", %{
        "subscription" => %{
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "30"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/devices/#{device.id}/subscriptions")
      assert flash["info"] == "Subscription saved"

      [sub] = Collector.list_subscriptions_for_device(device.id)
      assert "/interfaces/interface/state/counters" in sub.paths
      assert "/system/state/hostname" in sub.paths
    end

    test "submitting 30 seconds stores 30_000_000_000 ns in DB", %{conn: conn} do
      device = create_device()

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Select a path first
      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      view
      |> form("form", %{
        "subscription" => %{
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "30"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/devices/#{device.id}/subscriptions")
      assert flash["info"] == "Subscription saved"

      [sub] = Collector.list_subscriptions_for_device(device.id)
      assert sub.sample_interval_ns == 30_000_000_000
    end

    test "submitting 10 seconds stores 10_000_000_000 ns in DB", %{conn: conn} do
      device = create_device()

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Select a path first
      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      view
      |> form("form", %{
        "subscription" => %{
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "10"
        }
      })
      |> render_submit()

      assert_redirect(view, ~p"/devices/#{device.id}/subscriptions")
      [sub] = Collector.list_subscriptions_for_device(device.id)
      assert sub.sample_interval_ns == 10_000_000_000
    end

    test "toggling a selected path off deselects it", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Select a path
      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      html = render(view)
      assert html =~ "1 selected"

      # Deselect the same path
      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      html = render(view)
      assert html =~ "0 selected"
    end

    test "submitting with no paths selected shows validation error", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Submit without selecting any paths
      view
      |> form("form", %{
        "subscription" => %{
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "30"
        }
      })
      |> render_submit()

      # Should show error flash, not redirect
      html = render(view)
      assert html =~ "paths"
    end

    test "submitting with invalid sample_interval defaults to 30s", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/interfaces/interface/state/counters"]|)
      |> render_click()

      view
      |> form("form", %{
        "subscription" => %{
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "invalid"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/devices/#{device.id}/subscriptions")
      assert flash["info"] == "Subscription saved"

      [sub] = Collector.list_subscriptions_for_device(device.id)
      assert sub.sample_interval_ns == 30_000_000_000
    end

    test "clicking enumerate_from_device shows loading state", %{conn: conn} do
      device = create_device()
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      # Click enumerate - it will spawn a task that will fail (no mock) but we can
      # verify the loading state is set immediately
      html =
        view
        |> element(~s|button[phx-click="enumerate_from_device"]|)
        |> render_click()

      assert html =~ "Enumerating..."
    end
  end

  describe "Index - Edit Subscription" do
    test "navigates to edit subscription form", %{conn: conn} do
      device = create_device()
      sub = create_subscription(device)

      {:ok, _view, html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      assert html =~ "Edit Subscription"
    end

    test "edit form displays interval in seconds", %{conn: conn} do
      device = create_device()
      sub = create_subscription(device, %{"sample_interval_ns" => 10_000_000_000})

      {:ok, _view, html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      # 10_000_000_000 ns = 10 seconds
      assert html =~ ~s(value="10")
      assert html =~ "Sample Interval (seconds)"
    end

    test "edit form pre-selects existing paths", %{conn: conn} do
      device = create_device()

      sub =
        create_subscription(device, %{
          "paths" => ["/interfaces/interface/state/counters", "/system/state/hostname"]
        })

      {:ok, _view, html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      assert html =~ "2 selected"
    end

    test "updates an existing subscription via edit form", %{conn: conn} do
      device = create_device()

      sub =
        create_subscription(device, %{
          "paths" => ["/interfaces/interface/state/counters"]
        })

      {:ok, view, _html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      # Add another path
      view
      |> element(~s|input[phx-click="toggle_path"][phx-value-path="/system/state/hostname"]|)
      |> render_click()

      view
      |> form("form", %{
        "subscription" => %{
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "15"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/devices/#{device.id}/subscriptions")
      assert flash["info"] == "Subscription saved"

      updated = Collector.get_subscription!(sub.id)
      assert "/interfaces/interface/state/counters" in updated.paths
      assert "/system/state/hostname" in updated.paths
      assert updated.sample_interval_ns == 15_000_000_000
    end

    test "edit form shows orphaned paths under custom category", %{conn: conn} do
      device = create_device()

      # Create subscription with a path not in the available list
      sub =
        create_subscription(device, %{
          "paths" => [
            "/interfaces/interface/state/counters",
            "/custom/vendor/specific/path"
          ]
        })

      {:ok, _view, html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      assert html =~ "2 selected"
      assert html =~ "/custom/vendor/specific/path"
      assert html =~ "custom"
      assert html =~ "Custom path"
    end
  end

  describe "Index - Enumerate result forwarding" do
    test "enumerate error result displays error message", %{conn: conn} do
      device = create_device()

      sub =
        create_subscription(device, %{
          "paths" => ["/interfaces/interface/state/counters"]
        })

      {:ok, view, _html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      # Send enumerate error result - component ID is the subscription ID
      send(view.pid, {:enumerate_result, sub.id, {:error, :connection_refused}})

      # Allow time for the message to be processed
      _ = render(view)
      html = render(view)
      assert html =~ "Failed to enumerate paths"
      assert html =~ "connection_refused"
    end

    test "enumerate success result reloads paths and clears loading", %{conn: conn} do
      device = create_device()

      sub =
        create_subscription(device, %{
          "paths" => ["/interfaces/interface/state/counters"]
        })

      {:ok, view, _html} =
        live(conn, ~p"/devices/#{device.id}/subscriptions/#{sub.id}/edit")

      # Send enumerate success result
      send(view.pid, {:enumerate_result, sub.id, {:ok, %{paths: ["/discovered/path"], model: nil}}})

      _ = render(view)
      html = render(view)
      # Should not show error, should still have paths
      refute html =~ "Failed to enumerate"
      assert html =~ "Subscription Paths"
    end
  end
end
