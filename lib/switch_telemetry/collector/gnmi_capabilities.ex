defmodule SwitchTelemetry.Collector.GnmiCapabilities do
  @moduledoc """
  Fetches gNMI Capabilities from a device to discover supported paths and models.
  """
  require Logger

  alias SwitchTelemetry.Collector.{Helpers, SubscriptionPaths, TlsHelper}
  alias SwitchTelemetry.Devices

  @connect_timeout 10_000
  @rpc_timeout 30_000

  @type model_info :: %{name: String.t(), organization: String.t(), version: String.t()}

  @platform_model_patterns [
    {~r/Cisco-IOS-XR.*-asr9k/i, "ASR9K"},
    {~r/Cisco-IOS-XR.*-ncs5500/i, "NCS5500"},
    {~r/Cisco-IOS-XR.*-ncs540/i, "NCS540"},
    {~r/Cisco-IOS-XR.*-xrv9k/i, "XRv9K"},
    {~r/Cisco-NX-OS.*-n9k/i, "N9K"},
    {~r/Cisco-NX-OS.*-n3k/i, "N3K"},
    {~r/Cisco-IOS-XE.*-cat9k/i, "CAT9K"},
    {~r/Cisco-IOS-XE.*-isr4k/i, "ISR4K"},
    {~r/Arista-EOS/i, "ARISTA"},
    {~r/junos/i, "JUNOS"},
    {~r/nokia-sros/i, "SROS"}
  ]

  @doc """
  Fetches capabilities from a device via the gNMI Capabilities unary RPC.

  Returns `{:ok, %{paths: [...], device_model: "..." | nil}}`.
  """
  @spec fetch_capabilities(Devices.Device.t()) ::
          {:ok, %{paths: [String.t()], device_model: String.t() | nil}} | {:error, term()}
  def fetch_capabilities(device) do
    credential = Helpers.load_credential(device)
    grpc_opts = TlsHelper.build_grpc_opts(device.secure_mode, credential)
    grpc_opts = Keyword.merge(grpc_opts, adapter_opts: [connect_timeout: @connect_timeout])
    target = "#{device.ip_address}:#{device.gnmi_port}"

    with {:ok, channel} <- Helpers.grpc_client().connect(target, grpc_opts),
         {:ok, response} <-
           Helpers.grpc_client().capabilities(channel, %Gnmi.CapabilityRequest{},
             timeout: @rpc_timeout
           ) do
      Helpers.grpc_client().disconnect(channel)

      models = extract_models(response)
      paths = models_to_paths(models, device.platform)
      device_model = infer_device_model(Enum.map(models, & &1.name), device.platform)

      {:ok, %{paths: paths, device_model: device_model}}
    else
      {:error, reason} ->
        Logger.warning("Capabilities fetch failed for #{device.hostname}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches supported paths from a device via gNMI Capabilities RPC.

  Thin wrapper around `fetch_capabilities/1` for backward compatibility.
  """
  @spec fetch_paths(Devices.Device.t()) :: {:ok, [String.t()]} | {:error, term()}
  def fetch_paths(device) do
    case fetch_capabilities(device) do
      {:ok, %{paths: paths}} -> {:ok, paths}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates device-specific path overrides from fetched paths.

  Keys on `device.model` when available, falling back to `"<platform>_<id>"`.
  """
  @spec update_device_paths(Devices.Device.t(), [String.t()]) :: :ok
  def update_device_paths(device, paths) do
    model_id =
      if device.model && device.model != "" do
        device.model
      else
        "#{device.platform}_#{device.id}"
      end

    path_entries =
      Enum.map(paths, fn path ->
        %{
          path: path,
          description: "Discovered via gNMI Capabilities",
          category: "discovered"
        }
      end)

    SubscriptionPaths.save_device_override(model_id, path_entries)
  end

  @doc """
  Orchestrator that fetches capabilities, saves paths to model-specific override file,
  and updates device model if discovered.

  Returns `{:ok, %{paths: [...], model: "..." | nil}}`.
  """
  @spec enumerate_and_save(Devices.Device.t()) ::
          {:ok, %{paths: [String.t()], model: String.t() | nil}} | {:error, term()}
  def enumerate_and_save(device) do
    case fetch_capabilities(device) do
      {:ok, %{paths: paths, device_model: model}} ->
        device =
          if model do
            case Devices.update_device_model(device, model) do
              {:ok, updated_device} -> updated_device
              {:error, _} -> device
            end
          else
            device
          end

        update_device_paths(device, paths)
        {:ok, %{paths: paths, model: model}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Infers a device model string from YANG model names and platform.

  Matches model names against known platform-model patterns. Returns the first match
  or `nil` if no pattern matches.
  """
  @spec infer_device_model([String.t()], atom()) :: String.t() | nil
  def infer_device_model(model_names, _platform) do
    Enum.find_value(model_names, fn name ->
      Enum.find_value(@platform_model_patterns, fn {pattern, model} ->
        if Regex.match?(pattern, name), do: model
      end)
    end)
  end

  # --- Private ---

  defp extract_models(%Gnmi.CapabilityResponse{supported_models: models}) do
    Enum.map(models || [], fn model ->
      %{
        name: Map.get(model, :name, ""),
        organization: Map.get(model, :organization, ""),
        version: Map.get(model, :version, "")
      }
    end)
  end

  @known_model_paths %{
    "openconfig-interfaces" => ["/interfaces/interface/state/counters"],
    "openconfig-bgp" => [
      "/network-instances/network-instance/protocols/protocol/bgp/neighbors/neighbor/state"
    ],
    "openconfig-system" => ["/system/state/hostname", "/system/memory/state"],
    "openconfig-platform" => ["/components/component/state"],
    "openconfig-lldp" => ["/lldp/interfaces/interface/neighbors/neighbor/state"],
    "openconfig-network-instance" => ["/network-instances/network-instance/state"]
  }

  defp models_to_paths(models, _platform) do
    models
    |> Enum.flat_map(fn %{name: name} ->
      Map.get(@known_model_paths, name, [])
    end)
    |> Enum.uniq()
  end
end
