defmodule SwitchTelemetry.Workers.DeviceDiscoveryTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Workers.DeviceDiscovery

  describe "module" do
    test "uses Oban.Worker" do
      assert {:module, DeviceDiscovery} = Code.ensure_loaded(DeviceDiscovery)
      # Oban workers implement perform/1
      assert DeviceDiscovery.__info__(:functions) |> Keyword.has_key?(:perform)
    end

    test "perform succeeds with no devices" do
      assert :ok == DeviceDiscovery.perform(%Oban.Job{})
    end

    test "is configured for the discovery queue" do
      assert DeviceDiscovery.__opts__()[:queue] == :discovery
    end

    test "has max_attempts of 3" do
      assert DeviceDiscovery.__opts__()[:max_attempts] == 3
    end
  end

  describe "perform/1 with devices" do
    test "succeeds with an unassigned active device" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "unassigned-router",
          ip_address: "10.0.2.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active
        })

      assert :ok == DeviceDiscovery.perform(%Oban.Job{})

      # Device should still be active (no collector available to assign, but no error)
      updated = SwitchTelemetry.Devices.get_device!(device.id)
      assert updated.status == :active
    end

    test "marks device as unreachable when heartbeat is stale" do
      stale_time = DateTime.add(DateTime.utc_now(), -120, :second)

      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "stale-router",
          ip_address: "10.0.1.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          collector_heartbeat: stale_time
        })

      assert :ok == DeviceDiscovery.perform(%Oban.Job{})

      updated = SwitchTelemetry.Devices.get_device!(device.id)
      assert updated.status == :unreachable
    end

    test "keeps device active when heartbeat is fresh" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "fresh-router",
          ip_address: "10.0.1.2",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          collector_heartbeat: DateTime.utc_now()
        })

      assert :ok == DeviceDiscovery.perform(%Oban.Job{})

      updated = SwitchTelemetry.Devices.get_device!(device.id)
      assert updated.status == :active
    end

    test "does not mark inactive devices as unreachable even with stale heartbeat" do
      stale_time = DateTime.add(DateTime.utc_now(), -120, :second)

      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "inactive-router",
          ip_address: "10.0.1.3",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :inactive,
          collector_heartbeat: stale_time
        })

      assert :ok == DeviceDiscovery.perform(%Oban.Job{})

      updated = SwitchTelemetry.Devices.get_device!(device.id)
      assert updated.status == :inactive
    end

    test "does not mark device without heartbeat as unreachable" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: Ecto.UUID.generate(),
          hostname: "no-heartbeat-router",
          ip_address: "10.0.1.4",
          platform: :cisco_iosxr,
          transport: :gnmi,
          status: :active,
          collector_heartbeat: nil
        })

      assert :ok == DeviceDiscovery.perform(%Oban.Job{})

      updated = SwitchTelemetry.Devices.get_device!(device.id)
      assert updated.status == :active
    end
  end
end
