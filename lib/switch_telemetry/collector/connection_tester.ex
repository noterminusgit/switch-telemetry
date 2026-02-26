defmodule SwitchTelemetry.Collector.ConnectionTester do
  @moduledoc """
  Lightweight connection probes for gNMI and NETCONF protocols.

  Tests device reachability by attempting to connect, perform a basic operation,
  and disconnect. Returns structured results with timing information.
  """
  require Logger

  alias SwitchTelemetry.Collector.{Helpers, TlsHelper}

  @type protocol :: :gnmi | :netconf
  @type test_result :: %{
          protocol: protocol(),
          success: boolean(),
          message: String.t(),
          elapsed_ms: non_neg_integer()
        }

  @connect_timeout 10_000
  @rpc_timeout 30_000
  @channel_timeout 30_000

  @spec test_connection(Devices.Device.t()) :: [test_result()]
  def test_connection(device) do
    case device.transport do
      :gnmi -> [test_gnmi(device)]
      :netconf -> [test_netconf(device)]
      :both -> [test_gnmi(device), test_netconf(device)]
    end
  end

  @spec test_gnmi(Devices.Device.t()) :: test_result()
  def test_gnmi(device) do
    start_time = System.monotonic_time(:millisecond)

    credential = Helpers.load_credential(device)
    grpc_opts = TlsHelper.build_grpc_opts(device.secure_mode, credential)
    grpc_opts = Keyword.merge(grpc_opts, adapter_opts: [connect_timeout: @connect_timeout])
    target = "#{device.ip_address}:#{device.gnmi_port}"

    result =
      case Helpers.grpc_client().connect(target, grpc_opts) do
        {:ok, channel} ->
          cap_result =
            Helpers.grpc_client().capabilities(channel, %Gnmi.CapabilityRequest{},
              timeout: @rpc_timeout
            )

          Helpers.grpc_client().disconnect(channel)

          case cap_result do
            {:ok, _response} -> {:ok, "gNMI connection successful"}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end

    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, message} ->
        %{protocol: :gnmi, success: true, message: message, elapsed_ms: elapsed_ms}

      {:error, reason} ->
        %{protocol: :gnmi, success: false, message: format_error(reason), elapsed_ms: elapsed_ms}
    end
  end

  @spec test_netconf(Devices.Device.t()) :: test_result()
  def test_netconf(device) do
    start_time = System.monotonic_time(:millisecond)

    result =
      case Helpers.load_credential(device) do
        nil ->
          {:error, :no_credential}

        credential ->
          do_test_netconf(device, credential)
      end

    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, message} ->
        %{protocol: :netconf, success: true, message: message, elapsed_ms: elapsed_ms}

      {:error, reason} ->
        %{
          protocol: :netconf,
          success: false,
          message: format_error(reason),
          elapsed_ms: elapsed_ms
        }
    end
  end

  defp do_test_netconf(device, credential) do
    ssh_opts = [
      {:user, String.to_charlist(credential.username)},
      {:silently_accept_hosts, true},
      {:connect_timeout, @connect_timeout}
    ]

    ssh_opts =
      if credential.password do
        [{:password, String.to_charlist(credential.password)} | ssh_opts]
      else
        ssh_opts
      end

    case Helpers.ssh_client().connect(
           String.to_charlist(device.ip_address),
           device.netconf_port,
           ssh_opts
         ) do
      {:ok, ssh_ref} ->
        result =
          with {:ok, channel_id} <-
                 Helpers.ssh_client().session_channel(ssh_ref, @channel_timeout),
               :success <-
                 Helpers.ssh_client().subsystem(
                   ssh_ref,
                   channel_id,
                   ~c"netconf",
                   @channel_timeout
                 ) do
            {:ok, "NETCONF connection successful"}
          else
            :failure -> {:error, :netconf_subsystem_failed}
            {:error, reason} -> {:error, reason}
          end

        Helpers.ssh_client().close(ssh_ref)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec format_error(term()) :: String.t()
  defp format_error(:timeout), do: "Connection timed out"
  defp format_error(:econnrefused), do: "Connection refused"
  defp format_error(:econnreset), do: "Connection reset"
  defp format_error(:ehostunreach), do: "Host unreachable"
  defp format_error(:enetunreach), do: "Network unreachable"
  defp format_error(:nxdomain), do: "DNS resolution failed"
  defp format_error(:no_credential), do: "No credential configured for NETCONF"
  defp format_error(:netconf_subsystem_failed), do: "NETCONF subsystem negotiation failed"
  defp format_error(reason), do: "Connection failed: #{inspect(reason)}"
end
