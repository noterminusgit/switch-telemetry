defmodule SwitchTelemetry.Collector.GnmiCapabilitiesTest do
  use SwitchTelemetry.DataCase, async: false

  import Mox

  alias SwitchTelemetry.Collector.GnmiCapabilities
  alias SwitchTelemetry.Collector.MockGrpcClient

  setup :verify_on_exit!

  setup do
    # Point paths_dir at a tmp dir so tests don't write into priv/
    tmp_dir = Path.join(System.tmp_dir!(), "gnmi_caps_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp_dir, "device_overrides"))

    prev_paths = Application.get_env(:switch_telemetry, :gnmi_paths_dir)
    Application.put_env(:switch_telemetry, :gnmi_paths_dir, tmp_dir)

    prev_env = Application.get_env(:switch_telemetry, :grpc_client)
    Application.put_env(:switch_telemetry, :grpc_client, MockGrpcClient)

    on_exit(fn ->
      if prev_paths do
        Application.put_env(:switch_telemetry, :gnmi_paths_dir, prev_paths)
      else
        Application.delete_env(:switch_telemetry, :gnmi_paths_dir)
      end

      if prev_env do
        Application.put_env(:switch_telemetry, :grpc_client, prev_env)
      else
        Application.delete_env(:switch_telemetry, :grpc_client)
      end

      File.rm_rf!(tmp_dir)
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

    {:ok, device: device, tmp_dir: tmp_dir}
  end

  describe "fetch_paths/1" do
    test "returns error when device is unreachable", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts ->
        {:error, :connection_refused}
      end)

      assert {:error, :connection_refused} = GnmiCapabilities.fetch_paths(device)
    end

    test "returns paths from capabilities response", %{device: device} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [
          %Gnmi.ModelData{name: "openconfig-interfaces", organization: "OpenConfig", version: "3.0.0"},
          %Gnmi.ModelData{name: "openconfig-system", organization: "OpenConfig", version: "1.0.0"}
        ],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{} -> {:ok, response} end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      assert {:ok, paths} = GnmiCapabilities.fetch_paths(device)
      assert "/interfaces/interface/state/counters" in paths
      assert "/system/state/hostname" in paths
      assert "/system/memory/state" in paths
    end
  end

  describe "fetch_capabilities/1" do
    test "returns error when device is unreachable", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts ->
        {:error, :connection_refused}
      end)

      assert {:error, :connection_refused} = GnmiCapabilities.fetch_capabilities(device)
    end

    test "returns paths and device model from capabilities", %{device: device} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [
          %Gnmi.ModelData{name: "openconfig-interfaces", organization: "OpenConfig", version: "3.0.0"},
          %Gnmi.ModelData{name: "Cisco-IOS-XR-asr9k-something", organization: "Cisco", version: "1.0.0"}
        ],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{} -> {:ok, response} end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      assert {:ok, %{paths: paths, device_model: model}} =
               GnmiCapabilities.fetch_capabilities(device)

      assert "/interfaces/interface/state/counters" in paths
      assert model == "ASR9K"
    end

    test "returns nil device_model when no patterns match", %{device: device} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [
          %Gnmi.ModelData{name: "openconfig-interfaces", organization: "OpenConfig", version: "3.0.0"}
        ],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{} -> {:ok, response} end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      assert {:ok, %{device_model: nil}} = GnmiCapabilities.fetch_capabilities(device)
    end
  end

  describe "infer_device_model/2" do
    test "matches Cisco IOS-XR ASR9K model" do
      models = ["openconfig-interfaces", "Cisco-IOS-XR-asr9k-config"]
      assert GnmiCapabilities.infer_device_model(models, :cisco_iosxr) == "ASR9K"
    end

    test "matches Cisco NX-OS N9K model" do
      models = ["Cisco-NX-OS-device-n9k-config"]
      assert GnmiCapabilities.infer_device_model(models, :cisco_nxos) == "N9K"
    end

    test "matches Cisco IOS-XE CAT9K model" do
      models = ["Cisco-IOS-XE-native-cat9k"]
      assert GnmiCapabilities.infer_device_model(models, :cisco_iosxe) == "CAT9K"
    end

    test "returns nil when no patterns match" do
      models = ["openconfig-interfaces", "openconfig-system"]
      assert GnmiCapabilities.infer_device_model(models, :cisco_iosxr) == nil
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

    test "uses device model as key when available", %{device: device, tmp_dir: tmp_dir} do
      {:ok, device} = SwitchTelemetry.Devices.update_device(device, %{model: "ASR9K"})

      paths = ["/interfaces/interface/state/counters"]
      assert :ok = GnmiCapabilities.update_device_paths(device, paths)

      override_path = Path.join([tmp_dir, "device_overrides", "ASR9K.json"])
      assert File.exists?(override_path)
    end
  end

  describe "enumerate_and_save/1" do
    test "fetches capabilities, saves paths, and updates device model", %{device: device, tmp_dir: tmp_dir} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [
          %Gnmi.ModelData{name: "openconfig-interfaces", organization: "OpenConfig", version: "3.0.0"},
          %Gnmi.ModelData{name: "Cisco-IOS-XR-asr9k-config", organization: "Cisco", version: "1.0.0"}
        ],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{} -> {:ok, response} end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      assert {:ok, %{paths: paths, model: "ASR9K"}} =
               GnmiCapabilities.enumerate_and_save(device)

      assert "/interfaces/interface/state/counters" in paths

      # Check device model was updated in DB
      updated_device = SwitchTelemetry.Devices.get_device!(device.id)
      assert updated_device.model == "ASR9K"

      # Check override file was saved with model key
      override_path = Path.join([tmp_dir, "device_overrides", "ASR9K.json"])
      assert File.exists?(override_path)
    end

    test "returns error when device is unreachable", %{device: device} do
      MockGrpcClient
      |> expect(:connect, fn _target, _opts ->
        {:error, :connection_refused}
      end)

      assert {:error, :connection_refused} = GnmiCapabilities.enumerate_and_save(device)
    end

    test "fetches capabilities with credential loaded", context do
      # Create a credential and assign it to the device
      {:ok, credential} =
        SwitchTelemetry.Devices.create_credential(%{
          id: "cred-cap-#{System.unique_integer([:positive])}",
          name: "test-cred",
          username: "admin",
          password: "secret"
        })

      {:ok, device} =
        SwitchTelemetry.Devices.update_device(context.device, %{credential_id: credential.id})

      response = %Gnmi.CapabilityResponse{
        supported_models: [
          %Gnmi.ModelData{name: "openconfig-interfaces", organization: "OpenConfig", version: "3.0.0"}
        ],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{} -> {:ok, response} end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      assert {:ok, %{paths: paths, model: nil}} =
               GnmiCapabilities.enumerate_and_save(device)

      assert "/interfaces/interface/state/counters" in paths
    end

    test "saves with fallback key when no model detected", %{device: device, tmp_dir: tmp_dir} do
      response = %Gnmi.CapabilityResponse{
        supported_models: [
          %Gnmi.ModelData{name: "openconfig-interfaces", organization: "OpenConfig", version: "3.0.0"}
        ],
        supported_encodings: [],
        gNMI_version: "0.7.0"
      }

      MockGrpcClient
      |> expect(:connect, fn _target, _opts -> {:ok, :channel} end)
      |> expect(:capabilities, fn :channel, %Gnmi.CapabilityRequest{} -> {:ok, response} end)
      |> expect(:disconnect, fn :channel -> {:ok, :channel} end)

      assert {:ok, %{paths: paths, model: nil}} =
               GnmiCapabilities.enumerate_and_save(device)

      assert "/interfaces/interface/state/counters" in paths

      # Check fallback filename was used
      fallback_key = "cisco_iosxr_#{device.id}"
      override_path = Path.join([tmp_dir, "device_overrides", "#{fallback_key}.json"])
      assert File.exists?(override_path)
    end
  end
end
