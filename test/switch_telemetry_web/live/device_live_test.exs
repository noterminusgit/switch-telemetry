defmodule SwitchTelemetryWeb.DeviceLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias SwitchTelemetry.Devices

  setup :register_and_log_in_user

  describe "Index" do
    test "lists devices", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "Devices"
    end

    test "shows empty state when no devices", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "No devices found"
    end

    test "renders device rows when devices exist", %{conn: conn} do
      {:ok, _device} =
        Devices.create_device(%{
          id: "dev_idx1",
          hostname: "sw-test-01.lab",
          ip_address: "10.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "sw-test-01.lab"
      assert html =~ "10.0.0.1"
    end

    test "new device form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices/new")
      assert html =~ "Add Device"
    end

    test "filters by status", %{conn: conn} do
      {:ok, _} =
        Devices.create_device(%{
          id: "dev_filt1",
          hostname: "sw-active.lab",
          ip_address: "10.0.1.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active
        })

      {:ok, _} =
        Devices.create_device(%{
          id: "dev_filt2",
          hostname: "sw-maint.lab",
          ip_address: "10.0.1.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :maintenance
        })

      {:ok, view, _html} = live(conn, ~p"/devices")

      # Filter to active only
      html = view |> element("button[phx-value-status=active]") |> render_click()
      assert html =~ "sw-active.lab"
      refute html =~ "sw-maint.lab"
    end

    test "deletes a device", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_del1",
          hostname: "sw-delete.lab",
          ip_address: "10.0.2.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices")
      assert render(view) =~ "sw-delete.lab"

      view |> element("button[phx-value-id=#{device.id}]") |> render_click()
      refute render(view) =~ "sw-delete.lab"
    end

    test "filter_status with empty string resets to all devices", %{conn: conn} do
      {:ok, _} =
        Devices.create_device(%{
          id: "dev_reset_filt1",
          hostname: "sw-filter-reset.lab",
          ip_address: "10.0.3.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active
        })

      {:ok, view, _html} = live(conn, ~p"/devices")

      # First filter to active
      view |> element("button[phx-value-status=active]") |> render_click()
      assert render(view) =~ "sw-filter-reset.lab"

      # Then reset by clicking All (empty status)
      html = view |> element("button[phx-value-status=\"\"]") |> render_click()
      assert html =~ "sw-filter-reset.lab"
    end

    test "renders all status filter buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "All"
      assert html =~ "active"
      assert html =~ "inactive"
      assert html =~ "unreachable"
      assert html =~ "maintenance"
    end

    test "renders new device form fields", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/devices/new")
      assert html =~ "Hostname"
      assert html =~ "IP Address"
      assert html =~ "Platform"
      assert html =~ "Transport"
    end

    test "renders device table columns", %{conn: conn} do
      {:ok, _} =
        Devices.create_device(%{
          id: "dev_cols1",
          hostname: "sw-cols.lab",
          ip_address: "10.0.4.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active
        })

      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "Hostname"
      assert html =~ "IP Address"
      assert html =~ "Platform"
      assert html =~ "Transport"
      assert html =~ "Status"
      assert html =~ "Collector"
    end

    test "renders device assigned_collector as dash when nil", %{conn: conn} do
      {:ok, _} =
        Devices.create_device(%{
          id: "dev_no_collector",
          hostname: "sw-no-coll.lab",
          ip_address: "10.0.4.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          assigned_collector: nil
        })

      {:ok, _view, html} = live(conn, ~p"/devices")
      assert html =~ "sw-no-coll.lab"
      assert html =~ "-"
    end
  end

  describe "Show" do
    test "displays device details", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show1",
          hostname: "core-sw-01.dc1",
          ip_address: "10.0.10.1",
          platform: :juniper_junos,
          transport: :both,
          gnmi_port: 57400,
          netconf_port: 830
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "core-sw-01.dc1"
      assert html =~ "10.0.10.1"
      assert html =~ "juniper_junos"
      assert html =~ "57400"
      assert html =~ "830"
    end

    test "shows latest metrics section", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show2",
          hostname: "sw-metrics.lab",
          ip_address: "10.0.10.2",
          platform: :arista_eos,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Latest Metrics"
    end

    test "shows edit device link", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_edit",
          hostname: "show-edit.lab",
          ip_address: "10.0.11.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Edit Device"
    end

    test "shows manage subscriptions link", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_sub",
          hostname: "show-sub.lab",
          ip_address: "10.0.11.2",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Manage Subscriptions"
    end

    test "shows device status badge", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_status",
          hostname: "status-device.lab",
          ip_address: "10.0.11.3",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "active"
      assert html =~ "bg-green-100"
    end

    test "shows back to all devices link", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_back",
          hostname: "back-device.lab",
          ip_address: "10.0.11.4",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "All Devices"
    end

    test "shows no recent metrics when empty", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_empty_metrics",
          hostname: "empty-metrics.lab",
          ip_address: "10.0.11.5",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "No recent metrics"
    end

    test "shows device details section", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_details",
          hostname: "details.lab",
          ip_address: "10.0.11.6",
          platform: :cisco_iosxr,
          transport: :both,
          gnmi_port: 57400,
          netconf_port: 830,
          collection_interval_ms: 30000
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Device Details"
      assert html =~ "gNMI Port"
      assert html =~ "NETCONF Port"
      assert html =~ "Collection Interval"
      assert html =~ "30s"
    end

    test "shows Unassigned when no collector assigned", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_unassigned",
          hostname: "unassigned.lab",
          ip_address: "10.0.11.7",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Unassigned"
    end

    test "shows inactive status badge", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_inactive",
          hostname: "inactive-dev.lab",
          ip_address: "10.0.12.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :inactive
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "inactive"
      assert html =~ "bg-gray-100"
    end

    test "shows unreachable status badge", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_unreach",
          hostname: "unreachable-dev.lab",
          ip_address: "10.0.12.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :unreachable
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "unreachable"
      assert html =~ "bg-red-100"
    end

    test "shows maintenance status badge", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_maint",
          hostname: "maint-dev.lab",
          ip_address: "10.0.12.3",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :maintenance
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "maintenance"
      assert html =~ "bg-yellow-100"
    end

    test "shows device tags when present", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_tags",
          hostname: "tagged-dev.lab",
          ip_address: "10.0.12.4",
          platform: :cisco_iosxr,
          transport: :gnmi,
          tags: %{"env" => "production", "site" => "dc1"}
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "env"
      assert html =~ "production"
      assert html =~ "site"
      assert html =~ "dc1"
    end

    test "shows last seen timestamp when present", %{conn: conn} do
      now = DateTime.utc_now()

      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_lastseen",
          hostname: "lastseen-dev.lab",
          ip_address: "10.0.12.5",
          platform: :cisco_iosxr,
          transport: :gnmi,
          last_seen_at: now
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Last Seen"
      assert html =~ "UTC"
    end

    test "shows assigned collector name when present", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_assigned",
          hostname: "assigned-dev.lab",
          ip_address: "10.0.12.6",
          platform: :cisco_iosxr,
          transport: :gnmi,
          assigned_collector: "collector-node-01"
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "collector-node-01"
    end

    test "shows transport type in header", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_show_transport",
          hostname: "transport-dev.lab",
          ip_address: "10.0.12.7",
          platform: :cisco_iosxr,
          transport: :both
        })

      {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}")
      assert html =~ "Transport: both"
    end
  end

  describe "Show - PubSub metrics updates" do
    test "receives metrics via PubSub and updates the view", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_metrics",
          hostname: "pubsub-dev.lab",
          ip_address: "10.0.13.1",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      # Simulate PubSub gnmi_metrics message
      metric = %{
        time: DateTime.utc_now(),
        path: "/interfaces/interface/state/counters",
        source: "gnmi",
        value_float: 42.5,
        value_int: nil,
        value_str: nil
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, [metric]}
      )

      # Allow time for the message to be processed
      html = render(view)
      assert html =~ "/interfaces/interface/state/counters"
      assert html =~ "gnmi"
      assert html =~ "42.50"
    end

    test "receives netconf_metrics via PubSub", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_netconf",
          hostname: "pubsub-nc-dev.lab",
          ip_address: "10.0.13.2",
          platform: :juniper_junos,
          transport: :netconf
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      metric = %{
        time: DateTime.utc_now(),
        path: "/system/cpu/utilization",
        source: "netconf",
        value_float: nil,
        value_int: 78,
        value_str: nil
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:netconf_metrics, device.id, [metric]}
      )

      html = render(view)
      assert html =~ "/system/cpu/utilization"
      assert html =~ "netconf"
      assert html =~ "78"
    end

    test "metrics with string values are displayed", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_str",
          hostname: "pubsub-str-dev.lab",
          ip_address: "10.0.13.3",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      metric = %{
        time: DateTime.utc_now(),
        path: "/system/state/hostname",
        source: "gnmi",
        value_float: nil,
        value_int: nil,
        value_str: "core-router-01"
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, [metric]}
      )

      html = render(view)
      assert html =~ "core-router-01"
    end

    test "metrics with no values display dash", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_nil",
          hostname: "pubsub-nil-dev.lab",
          ip_address: "10.0.13.4",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      metric = %{
        time: DateTime.utc_now(),
        path: "/system/empty",
        source: "gnmi",
        value_float: nil,
        value_int: nil,
        value_str: nil
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, [metric]}
      )

      html = render(view)
      assert html =~ "/system/empty"
    end

    test "metrics are capped at 100 entries", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_cap",
          hostname: "pubsub-cap-dev.lab",
          ip_address: "10.0.13.5",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      # Send 110 metrics to test the cap
      metrics =
        for i <- 1..110 do
          %{
            time: DateTime.utc_now(),
            path: "/metrics/counter/#{i}",
            source: "gnmi",
            value_float: i * 1.0,
            value_int: nil,
            value_str: nil
          }
        end

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, metrics}
      )

      # The view should cap the total at 100
      # new_metrics ++ existing => [1..110] ++ [] => Enum.take(100) keeps 1..100
      html = render(view)
      assert html =~ "/metrics/counter/1"
      assert html =~ "/metrics/counter/100"
      # Metric 101+ should be dropped by the cap
      refute html =~ "/metrics/counter/101"
    end

    test "handles unknown messages gracefully", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_unknown",
          hostname: "pubsub-unknown-dev.lab",
          ip_address: "10.0.13.6",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      # Send an unknown message
      send(view.pid, {:some_unknown_event, "data"})

      # View should still render fine
      html = render(view)
      assert html =~ "pubsub-unknown-dev.lab"
    end

    test "format_time handles NaiveDateTime", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_naivetime",
          hostname: "pubsub-naive-dev.lab",
          ip_address: "10.0.13.7",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      metric = %{
        time: NaiveDateTime.utc_now(),
        path: "/system/naive-time",
        source: "gnmi",
        value_float: 1.23,
        value_int: nil,
        value_str: nil
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, [metric]}
      )

      html = render(view)
      assert html =~ "/system/naive-time"
      assert html =~ "1.23"
    end

    test "format_time handles nil time", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_pubsub_niltime",
          hostname: "pubsub-niltime-dev.lab",
          ip_address: "10.0.13.8",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      metric = %{
        time: nil,
        path: "/system/nil-time",
        source: "gnmi",
        value_float: 5.67,
        value_int: nil,
        value_str: nil
      }

      Phoenix.PubSub.broadcast(
        SwitchTelemetry.PubSub,
        "device:#{device.id}",
        {:gnmi_metrics, device.id, [metric]}
      )

      html = render(view)
      assert html =~ "/system/nil-time"
      # format_time returns "-" for nil
      assert html =~ "-"
    end
  end
end
