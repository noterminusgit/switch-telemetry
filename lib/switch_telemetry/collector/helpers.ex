defmodule SwitchTelemetry.Collector.Helpers do
  @moduledoc """
  Shared helper functions for collector modules.

  Centralizes credential loading and client dispatch that was previously
  duplicated across GnmiSession, NetconfSession, ConnectionTester, and
  GnmiCapabilities.
  """

  alias SwitchTelemetry.{Devices, Metrics}
  alias SwitchTelemetry.Collector.StreamMonitor

  @doc """
  Loads a device's credential by its `credential_id`, returning nil when
  the device has no credential or the credential no longer exists.
  """
  @spec load_credential(Devices.Device.t()) :: Devices.Credential.t() | nil
  def load_credential(device) do
    if device.credential_id, do: Devices.get_credential(device.credential_id)
  end

  @doc """
  Writes metrics to InfluxDB, broadcasts them via PubSub, and reports
  to StreamMonitor. No-op when the metrics list is empty.
  """
  @spec persist_and_broadcast([map()], String.t(), atom()) :: :ok
  def persist_and_broadcast([], _device_id, _source), do: :ok

  def persist_and_broadcast(metrics, device_id, source) do
    Metrics.insert_batch(metrics)
    msg = {:"#{source}_metrics", device_id, metrics}
    Phoenix.PubSub.broadcast(SwitchTelemetry.PubSub, "device:#{device_id}", msg)
    StreamMonitor.report_message(device_id, source)
    :ok
  end

  @base_retry_delay :timer.seconds(5)
  @max_retry_delay :timer.minutes(5)

  @doc """
  Computes exponential backoff delay for retry attempts, capped at 5 minutes.
  """
  @spec retry_delay(non_neg_integer()) :: non_neg_integer()
  def retry_delay(retry_count) do
    min(trunc(@base_retry_delay * :math.pow(2, retry_count)), @max_retry_delay)
  end

  @doc """
  Returns the configured gRPC client module, defaulting to DefaultGrpcClient.
  """
  @spec grpc_client() :: module()
  def grpc_client do
    Application.get_env(
      :switch_telemetry,
      :grpc_client,
      SwitchTelemetry.Collector.DefaultGrpcClient
    )
  end

  @doc """
  Returns the configured SSH client module, defaulting to DefaultSshClient.
  """
  @spec ssh_client() :: module()
  def ssh_client do
    Application.get_env(
      :switch_telemetry,
      :ssh_client,
      SwitchTelemetry.Collector.DefaultSshClient
    )
  end
end
