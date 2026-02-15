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

    test "creates a subscription via the form", %{conn: conn} do
      device = create_device()

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/subscriptions/new")

      view
      |> form("form", %{
        "subscription" => %{
          "paths" => "/interfaces/interface/state/counters\n/system/state/hostname",
          "mode" => "stream",
          "encoding" => "proto",
          "sample_interval_ns" => "30000000000"
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
  end
end
