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
  def query(device_id, path, time_range) do
    backend().query(device_id, path, time_range)
  end

  @doc """
  Query raw metrics with a given bucket size.
  bucket_size must be a valid interval string like "1 minute", "5 minutes", "1 hour".
  """
  def query_raw(device_id, path, bucket_size, time_range) do
    backend().query_raw(device_id, path, bucket_size, time_range)
  end

  @doc """
  Compute rate of change (per second) for counter metrics.
  """
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
