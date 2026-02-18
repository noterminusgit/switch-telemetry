defmodule SwitchTelemetry.Collector.GnmiCapabilitiesTest do
  use SwitchTelemetry.DataCase, async: true

  import Mox

  alias SwitchTelemetry.Collector.GnmiCapabilities
  alias SwitchTelemetry.Collector.MockGrpcClient

  setup :verify_on_exit!

  setup do
    prev_env = Application.get_env(:switch_telemetry, :grpc_client)
    Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)

    on_exit(fn ->
      if prev_env do
        Application.put_env(:switch_telemetry, :grpc_client, prev_env)
      else
        Application.delete_env(:switch_telemetry, :grpc_client)
      end
    end)

    {:ok, device} =
      SwitchTelemetry.Devices.create_device(%{
        id: "gnmi-cap-#{System.unique_integer([:positive])}",
        hostname: "sw-cap-#{System.unique_integer([:positive])}",
        ip_address: "10.8.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
        platform: :cisco_iosxr,
        transport: :gnmi,
        gnmi_port: 6030
      })

    {:ok, device: device}
  end

  describe "fetch_paths/1" do
    test "returns error when device is unreachable", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts ->
        {:error, :connection_refused}
      end)

      assert {:error, :connection_refused} = GnmiCapabilities.fetch_paths(device)
    end
  end

  describe "update_device_paths/2" do
    test "saves paths to device override file", %{device: device} do
      paths = [
        "/interfaces/interface/state/counters",
        "/system/state/hostname"
      ]

      assert :ok = GnmiCapabilities.update_device_paths(device, paths)
    end
  end
end
