defmodule SwitchTelemetry.Metrics do
  @moduledoc """
  Context for telemetry metrics ingestion and retrieval.
  Delegates to the configured backend (InfluxDB).
  """

  @doc """
  Insert a batch of metric data points.
  Expects a list of maps with keys: time, device_id, path, source, tags, value_float, value_int, value_str.
  """
  @spec insert_batch([map()]) :: {non_neg_integer(), nil}
  def insert_batch(metrics) when is_list(metrics) do
    backend().insert_batch(metrics)
  end

  @doc """
  Get the most recent metrics for a device.
  """
  @spec get_latest(String.t(), keyword()) :: [map()]
  def get_latest(device_id, opts \\ []) do
    backend().get_latest(device_id, opts)
  end

  @doc """
  Get time-bucketed aggregation for a device and path.
  """
  @spec get_time_series(
          String.t(),
          String.t(),
          String.t(),
          SwitchTelemetry.Metrics.Backend.time_range()
        ) :: [map()]
  def get_time_series(device_id, path, bucket_size, time_range) do
    backend().query_raw(device_id, path, bucket_size, time_range)
  end

  defp backend do
    Application.get_env(
      :switch_telemetry,
      :metrics_backend,
      SwitchTelemetry.Metrics.InfluxBackend
    )
  end
end
