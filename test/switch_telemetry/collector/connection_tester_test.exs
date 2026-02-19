defmodule SwitchTelemetry.Collector.ConnectionTesterTest do
  use SwitchTelemetry.DataCase, async: false

  import Mox

  alias SwitchTelemetry.Collector.ConnectionTester
  alias SwitchTelemetry.Collector.MockGrpcClient
  alias SwitchTelemetry.Collector.MockSshClient

  setup :verify_on_exit!

  setup do
    prev_grpc = Application.get_env(:switch_telemetry, :grpc_client)
    prev_ssh = Application.get_env(:switch_telemetry, :ssh_client)
    Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)
    Application.put_env(:switch_telemetry, :ssh_client, MockSshClient)

    on_exit(fn ->
      if prev_grpc,
        do: Application.put_env(:switch_telemetry, :grpc_client, prev_grpc),
        else: Application.delete_env(:switch_telemetry, :grpc_client)

      if prev_ssh,
        do: Application.put_env(:switch_telemetry, :ssh_client, prev_ssh),
        else: Application.delete_env(:switch_telemetry, :ssh_client)
    end)

    :ok
  end

  describe "test_gnmi/1" do
    setup do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: "conn-test-gnmi-#{System.unique_integer([:positive])}",
          hostname: "sw-conn-gnmi-#{System.unique_integer([:positive])}",
          ip_address: "10.20.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
          platform: :cisco_iosxr,
          transport: :gnmi,
          gnmi_port: 6030
        })

      {:ok, device: device}
    end

    test "success: connect + capabilities + disconnect returns success result", %{device: device} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{}, _opts ->
        {:ok, response}
      end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      result = ConnectionTester.test_gnmi(device)

      assert result.protocol == :gnmi
      assert result.success == true
      assert result.message =~ "gNMI"
      assert is_integer(result.elapsed_ms) and result.elapsed_ms >= 0
    end

    test "connect failure returns failure with message", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:error, :econnrefused} end)

      result = ConnectionTester.test_gnmi(device)

      assert result.protocol == :gnmi
      assert result.success == false
      assert result.message =~ "refused"
      assert is_integer(result.elapsed_ms)
    end

    test "timeout returns failure with timeout reason", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:error, :timeout} end)

      result = ConnectionTester.test_gnmi(device)

      assert result.protocol == :gnmi
      assert result.success == false
      assert result.message =~ "timed out"
    end

    test "channel is disconnected after capabilities failure", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{}, _opts ->
        {:error, :rpc_failed}
      end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      result = ConnectionTester.test_gnmi(device)

      assert result.success == false
    end

    test "returns elapsed_ms in result", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{}, _opts ->
        {:ok,
         %Gnmi.CapabilityResponse{
           supported_models: [],
           supported_encodings: [],
           gNMI_version: "0.7.0"
         }}
      end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      result = ConnectionTester.test_gnmi(device)

      assert is_integer(result.elapsed_ms)
      assert result.elapsed_ms >= 0
    end
  end

  describe "test_netconf/1" do
    setup do
      {:ok, credential} =
        SwitchTelemetry.Devices.create_credential(%{
          id: "cred-conn-#{System.unique_integer([:positive])}",
          name: "conn-test-cred",
          username: "admin",
          password: "secret"
        })

      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: "conn-test-nc-#{System.unique_integer([:positive])}",
          hostname: "sw-conn-nc-#{System.unique_integer([:positive])}",
          ip_address: "10.21.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
          platform: :cisco_iosxr,
          transport: :netconf,
          netconf_port: 830,
          credential_id: credential.id
        })

      {:ok, device: device, credential: credential}
    end

    test "success: SSH connect + session_channel + subsystem returns success", %{device: device} do
      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :ssh_ref} end)
      |> expect(:session_channel, fn :ssh_ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn :ssh_ref, 0, ~c"netconf", _timeout -> :success end)
      |> expect(:close, fn :ssh_ref -> :ok end)

      result = ConnectionTester.test_netconf(device)

      assert result.protocol == :netconf
      assert result.success == true
      assert result.message =~ "NETCONF"
      assert is_integer(result.elapsed_ms)
    end

    test "connect failure returns failure", %{device: device} do
      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:error, :econnrefused} end)

      result = ConnectionTester.test_netconf(device)

      assert result.protocol == :netconf
      assert result.success == false
      assert result.message =~ "refused"
    end

    test "subsystem failure returns failure", %{device: device} do
      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :ssh_ref} end)
      |> expect(:session_channel, fn :ssh_ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn :ssh_ref, 0, ~c"netconf", _timeout -> :failure end)
      |> expect(:close, fn :ssh_ref -> :ok end)

      result = ConnectionTester.test_netconf(device)

      assert result.protocol == :netconf
      assert result.success == false
      assert result.message =~ "subsystem"
    end

    test "SSH connection is closed after test", %{device: device} do
      test_pid = self()

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :ssh_ref} end)
      |> expect(:session_channel, fn :ssh_ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn :ssh_ref, 0, ~c"netconf", _timeout -> :success end)
      |> expect(:close, fn :ssh_ref ->
        send(test_pid, :ssh_closed)
        :ok
      end)

      ConnectionTester.test_netconf(device)

      assert_received :ssh_closed
    end

    test "handles missing credential gracefully" do
      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: "conn-test-nocred-#{System.unique_integer([:positive])}",
          hostname: "sw-conn-nocred-#{System.unique_integer([:positive])}",
          ip_address: "10.22.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
          platform: :cisco_iosxr,
          transport: :netconf,
          netconf_port: 830
        })

      result = ConnectionTester.test_netconf(device)

      assert result.protocol == :netconf
      assert result.success == false
      assert result.message =~ "credential"
    end
  end

  describe "test_connection/1" do
    setup do
      {:ok, credential} =
        SwitchTelemetry.Devices.create_credential(%{
          id: "cred-both-#{System.unique_integer([:positive])}",
          name: "both-cred",
          username: "admin",
          password: "secret"
        })

      {:ok, device} =
        SwitchTelemetry.Devices.create_device(%{
          id: "conn-test-both-#{System.unique_integer([:positive])}",
          hostname: "sw-conn-both-#{System.unique_integer([:positive])}",
          ip_address: "10.23.#{:rand.uniform(254)}.#{:rand.uniform(254)}",
          platform: :cisco_iosxr,
          transport: :both,
          gnmi_port: 6030,
          netconf_port: 830,
          credential_id: credential.id
        })

      {:ok, device: device}
    end

    test ":gnmi transport tests only gNMI", %{device: device} do
      device = %{device | transport: :gnmi}

      response = %Gnmi.CapabilityResponse{
        supported_models: [],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{}, _opts ->
        {:ok, response}
      end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      results = ConnectionTester.test_connection(device)

      assert length(results) == 1
      assert hd(results).protocol == :gnmi
    end

    test ":netconf transport tests only NETCONF", %{device: device} do
      device = %{device | transport: :netconf}

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :ssh_ref} end)
      |> expect(:session_channel, fn :ssh_ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn :ssh_ref, 0, ~c"netconf", _timeout -> :success end)
      |> expect(:close, fn :ssh_ref -> :ok end)

      results = ConnectionTester.test_connection(device)

      assert length(results) == 1
      assert hd(results).protocol == :netconf
    end

    test ":both transport tests both protocols", %{device: device} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{}, _opts ->
        {:ok, response}
      end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      MockSshClient
      |> expect(:connect, fn _host, _port, _opts -> {:ok, :ssh_ref} end)
      |> expect(:session_channel, fn :ssh_ref, _timeout -> {:ok, 0} end)
      |> expect(:subsystem, fn :ssh_ref, 0, ~c"netconf", _timeout -> :success end)
      |> expect(:close, fn :ssh_ref -> :ok end)

      results = ConnectionTester.test_connection(device)

      assert length(results) == 2
      protocols = Enum.map(results, & &1.protocol)
      assert :gnmi in protocols
      assert :netconf in protocols
    end
  end
end
