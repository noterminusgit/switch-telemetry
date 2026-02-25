defmodule SwitchTelemetry.Collector.HelpersTest do
  use SwitchTelemetry.DataCase, async: false

  import Mox

  alias SwitchTelemetry.Collector.Helpers
  alias SwitchTelemetry.Collector.MockGrpcClient
  alias SwitchTelemetry.Collector.MockSshClient
  alias SwitchTelemetry.Devices

  setup :verify_on_exit!

  # -- load_credential/1 --

  describe "load_credential/1" do
    test "returns credential when device has credential_id" do
      {:ok, cred} =
        Devices.create_credential(%{
          id: "cred_helper_#{System.unique_integer([:positive])}",
          name: "test-cred",
          username: "admin",
          password: "pass"
        })

      {:ok, device} =
        Devices.create_device(%{
          id: "dev_helper_#{System.unique_integer([:positive])}",
          hostname: "sw-helper-#{System.unique_integer([:positive])}",
          ip_address: "10.0.0.1",
          platform: :cisco_iosxr,
          transport: :gnmi,
          credential_id: cred.id
        })

      result = Helpers.load_credential(device)
      assert result.id == cred.id
      assert result.username == "admin"
    end

    test "returns nil when credential_id is nil" do
      {:ok, device} =
        Devices.create_device(%{
          id: "dev_no_cred_#{System.unique_integer([:positive])}",
          hostname: "sw-nocred-#{System.unique_integer([:positive])}",
          ip_address: "10.0.0.2",
          platform: :cisco_iosxr,
          transport: :gnmi
        })

      assert is_nil(Helpers.load_credential(device))
    end

    test "returns nil when credential_id references nonexistent credential" do
      # Use a struct directly to bypass FK constraint
      device = %SwitchTelemetry.Devices.Device{
        id: "dev_gone_test",
        credential_id: "cred_nonexistent_000"
      }

      assert is_nil(Helpers.load_credential(device))
    end
  end

  # -- grpc_client/0 + ssh_client/0 --

  describe "grpc_client/0" do
    test "returns default when not configured" do
      Application.delete_env(:switch_telemetry, :grpc_client)
      assert Helpers.grpc_client() == SwitchTelemetry.Collector.DefaultGrpcClient
    end

    test "returns configured mock" do
      Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)
      on_exit(fn -> Application.delete_env(:switch_telemetry, :grpc_client) end)
      assert Helpers.grpc_client() == MockGrpcClient
    end
  end

  describe "ssh_client/0" do
    test "returns default when not configured" do
      Application.delete_env(:switch_telemetry, :ssh_client)
      assert Helpers.ssh_client() == SwitchTelemetry.Collector.DefaultSshClient
    end

    test "returns configured mock" do
      Application.put_env(:switch_telemetry, :ssh_client, MockSshClient)
      on_exit(fn -> Application.delete_env(:switch_telemetry, :ssh_client) end)
      assert Helpers.ssh_client() == MockSshClient
    end
  end

  # -- persist_and_broadcast/3 --

  describe "persist_and_broadcast/3" do
    test "no-op for empty list" do
      assert :ok = Helpers.persist_and_broadcast([], "dev_123", :gnmi)
    end

    test "inserts and broadcasts metrics" do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "device:dev_broadcast_test")

      metrics = [
        %{
          time: DateTime.utc_now(),
          device_id: "dev_broadcast_test",
          path: "/test/path",
          source: :gnmi,
          value_float: 42.0,
          value_int: nil,
          value_str: nil
        }
      ]

      assert :ok = Helpers.persist_and_broadcast(metrics, "dev_broadcast_test", :gnmi)

      assert_receive {:gnmi_metrics, "dev_broadcast_test", ^metrics}, 1_000
    end

    test "builds correct atom for netconf source" do
      Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "device:dev_nc_test")

      metrics = [
        %{
          time: DateTime.utc_now(),
          device_id: "dev_nc_test",
          path: "/test/nc",
          source: :netconf,
          value_float: 1.0,
          value_int: nil,
          value_str: nil
        }
      ]

      assert :ok = Helpers.persist_and_broadcast(metrics, "dev_nc_test", :netconf)

      assert_receive {:netconf_metrics, "dev_nc_test", ^metrics}, 1_000
    end
  end

  # -- retry_delay/1 --

  describe "retry_delay/1" do
    test "starts at base delay (5s)" do
      assert Helpers.retry_delay(0) == 5_000
    end

    test "doubles with each retry" do
      assert Helpers.retry_delay(1) == 10_000
      assert Helpers.retry_delay(2) == 20_000
      assert Helpers.retry_delay(3) == 40_000
    end

    test "caps at 5 minutes" do
      assert Helpers.retry_delay(10) == 300_000
      assert Helpers.retry_delay(100) == 300_000
    end

    test "returns integer" do
      assert is_integer(Helpers.retry_delay(0))
      assert is_integer(Helpers.retry_delay(5))
    end
  end
end
