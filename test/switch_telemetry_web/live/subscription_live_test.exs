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
  end

  describe "Index - New Subscription" do
    test "navigates to new subscription form", %{conn: conn} do
      device = create_device()

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")
      assert html =~ "New Subscription"
      assert html =~ "Paths (one per line)"
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

    test "submitting 30 seconds stores 30_000_000_000 ns in DB", %{conn: conn} do
      device = create_device()

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      view
      |> form("form", %{
        "subscription" => %{
          "paths" => "/interfaces/interface/state/counters",
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

      view
      |> form("form", %{
        "subscription" => %{
          "paths" => "/interfaces/interface/state/counters",
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

    test "creates a subscription via the form", %{conn: conn} do
      device = create_device()

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      view
      |> form("form", %{
        "subscription" => %{
          "paths" => "/interfaces/interface/state/counters\n/system/state/hostname",
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_seconds" => "30"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/devices/#{device.id}/subscriptions")
      assert flash["info"] == "Subscription saved"
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
  end
end
