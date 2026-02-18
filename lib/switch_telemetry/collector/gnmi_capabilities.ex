defmodule SwitchTelemetry.Collector.GnmiCapabilities do
  @moduledoc """
  Fetches gNMI Capabilities from a device to discover supported paths and models.
  """
  require Logger

  alias SwitchTelemetry.Collector.{SubscriptionPaths, TlsHelper}
  alias SwitchTelemetry.Devices

  @type model_info :: %{name: String.t(), organization: String.t(), version: String.t()}

  @doc """
  Fetches supported paths from a device via gNMI Capabilities RPC.

  Returns a list of paths derived from the device's supported YANG models.
  """
  @spec fetch_paths(SwitchTelemetry.Devices.Device.t()) :: {:ok, [String.t()]} | {:error, term()}
  def fetch_paths(device) do
    credential = load_credential(device)
    grpc_opts = TlsHelper.build_grpc_opts(credential)
    target = "#{device.ip_address}:#{device.gnmi_port}"

    with {:ok, channel} <- grpc_client().connect(target, grpc_opts),
         stream <- grpc_client().subscribe(channel),
         :ok <- send_capabilities_request(stream),
         {:ok, models} <- recv_capabilities_response(stream) do
      grpc_client().disconnect(channel)
      paths = models_to_paths(models, device.platform)
      {:ok, paths}
    else
      {:error, reason} ->
        Logger.warning("Capabilities fetch failed for #{device.hostname}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Updates device-specific path overrides from fetched paths.
  """
  @spec update_device_paths(SwitchTelemetry.Devices.Device.t(), [String.t()]) :: :ok
  def update_device_paths(device, paths) do
    model_id = "#{device.platform}_#{device.id}"

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

  # --- Private ---

  defp send_capabilities_request(stream) do
    request = %Gnmi.CapabilityRequest{}

    try do
      grpc_client().send_request(stream, request)
      :ok
    rescue
      e -> {:error, e}
    end
  end

  defp recv_capabilities_response(stream) do
    case grpc_client().recv(stream) do
      {:ok, response_stream} ->
        models =
          response_stream
          |> Enum.reduce([], fn
            {:ok, %Gnmi.CapabilityResponse{supported_models: models}}, acc ->
              extracted =
                Enum.map(models || [], fn model ->
                  %{
                    name: Map.get(model, :name, ""),
                    organization: Map.get(model, :organization, ""),
                    version: Map.get(model, :version, "")
                  }
                end)

              acc ++ extracted

            _, acc ->
              acc
          end)

        {:ok, models}

      {:error, reason} ->
        {:error, reason}
    end
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

  defp load_credential(device) do
    if device.credential_id do
      try do
        Devices.get_credential!(device.credential_id)
      rescue
        Ecto.NoResultsError -> nil
      end
    else
      nil
    end
  end

  defp grpc_client do
    Application.get_env(
      :switch_telemetry,
      :grpc_client,
      SwitchTelemetry.Collector.DefaultGrpcClient
    )
  end
end
