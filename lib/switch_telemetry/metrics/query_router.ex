defmodule SwitchTelemetry.Metrics.QueryRouter do
  @moduledoc """
  Routes metric queries to the most efficient data source:
  - Raw bucket for short ranges (< 1 hour)
  - 5-minute downsampled bucket for medium ranges (1h - 24h)
  - 1-hour downsampled bucket for long ranges (> 24h)
  """

  @doc """
  Query metrics with automatic source routing based on time range duration.
  Returns a list of maps with :bucket, :avg_value, :max_value, :min_value, :sample_count.
  """
  @spec query(String.t(), String.t(), SwitchTelemetry.Metrics.Backend.time_range()) :: [map()]
  def query(device_id, path, time_range) do
    backend().query(device_id, path, time_range)
  end

  @doc """
  Query raw metrics with a given bucket size.
  bucket_size must be a valid interval string like "1 minute", "5 minutes", "1 hour".
  """
  @spec query_raw(
          String.t(),
          String.t(),
          String.t(),
          SwitchTelemetry.Metrics.Backend.time_range()
        ) :: [map()]
  def query_raw(device_id, path, bucket_size, time_range) do
    backend().query_raw(device_id, path, bucket_size, time_range)
  end

  @doc """
  Query metrics where the path starts with the given prefix.
  Returns results grouped by full path: [%{path: String.t(), data: [%{bucket: DateTime.t(), avg_value: float()}]}].
  """
  @spec query_by_prefix(String.t(), String.t(), SwitchTelemetry.Metrics.Backend.time_range()) ::
          [map()]
  def query_by_prefix(device_id, path_prefix, time_range) do
    backend().query_by_prefix(device_id, path_prefix, time_range)
  end

  @doc """
  Compute rate of change (per second) for counter metrics.
  """
  @spec query_rate(
          String.t(),
          String.t(),
          String.t(),
          SwitchTelemetry.Metrics.Backend.time_range()
        ) :: [map()]
  def query_rate(device_id, path, bucket_size, time_range) do
    backend().query_rate(device_id, path, bucket_size, time_range)
  end

  defp backend do
    Application.get_env(
      :switch_telemetry,
      :metrics_backend,
      SwitchTelemetry.Metrics.InfluxBackend
    )
  end
end
