defmodule SwitchTelemetry.Metrics.QueryRouter do
  @moduledoc """
  Routes metric queries to the most efficient data source:
  - Raw hypertable for short ranges (< 1 hour)
  - 5-minute continuous aggregate for medium ranges (1h - 24h)
  - 1-hour continuous aggregate for long ranges (> 24h)
  """
  alias SwitchTelemetry.Repo

  @valid_bucket_sizes ["10 seconds", "30 seconds", "1 minute", "5 minutes", "15 minutes", "1 hour"]

  @doc """
  Query metrics with automatic source routing based on time range duration.
  Returns a list of maps with :bucket, :avg_value, :max_value, :min_value, :sample_count.
  """
  def query(device_id, path, time_range) do
    duration_seconds = DateTime.diff(time_range.end, time_range.start)

    cond do
      duration_seconds <= 3_600 ->
        query_raw(device_id, path, "10 seconds", time_range)

      duration_seconds <= 86_400 ->
        query_aggregate("metrics_5m", device_id, path, time_range)

      true ->
        query_aggregate("metrics_1h", device_id, path, time_range)
    end
  end

  @doc """
  Query raw metrics table with a given bucket size.
  bucket_size must be a valid PostgreSQL interval string.
  """
  def query_raw(device_id, path, bucket_size, time_range)
      when bucket_size in @valid_bucket_sizes do
    Repo.query!(
      """
      SELECT
        time_bucket('#{bucket_size}', time) AS bucket,
        avg(value_float) AS avg_value,
        max(value_float) AS max_value,
        min(value_float) AS min_value,
        count(*) AS sample_count
      FROM metrics
      WHERE device_id = $1
        AND path = $2
        AND time >= $3
        AND time <= $4
        AND value_float IS NOT NULL
      GROUP BY bucket
      ORDER BY bucket
      """,
      [device_id, path, time_range.start, time_range.end]
    )
    |> postgrex_to_maps()
  end

  @doc """
  Query a continuous aggregate (metrics_5m or metrics_1h).
  """
  def query_aggregate(table, device_id, path, time_range)
      when table in ["metrics_5m", "metrics_1h"] do
    Repo.query!(
      """
      SELECT
        bucket,
        avg_value,
        max_value,
        min_value,
        sample_count
      FROM #{table}
      WHERE device_id = $1
        AND path = $2
        AND bucket >= $3
        AND bucket <= $4
      ORDER BY bucket
      """,
      [device_id, path, time_range.start, time_range.end]
    )
    |> postgrex_to_maps()
  end

  @doc """
  Compute rate of change (per second) for counter metrics.
  """
  def query_rate(device_id, path, bucket_size, time_range)
      when bucket_size in @valid_bucket_sizes do
    Repo.query!(
      """
      SELECT
        time_bucket('#{bucket_size}', time) AS bucket,
        (max(value_int) - min(value_int)) /
          EXTRACT(EPOCH FROM '#{bucket_size}'::interval) AS rate_per_sec
      FROM metrics
      WHERE device_id = $1
        AND path = $2
        AND time >= $3
        AND time <= $4
        AND value_int IS NOT NULL
      GROUP BY bucket
      ORDER BY bucket
      """,
      [device_id, path, time_range.start, time_range.end]
    )
    |> postgrex_to_maps()
  end

  defp postgrex_to_maps(%Postgrex.Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new(fn {col, val} -> {safe_column_to_atom(col), val} end)
    end)
  end

  defp safe_column_to_atom("bucket"), do: :bucket
  defp safe_column_to_atom("avg_value"), do: :avg_value
  defp safe_column_to_atom("max_value"), do: :max_value
  defp safe_column_to_atom("min_value"), do: :min_value
  defp safe_column_to_atom("sample_count"), do: :sample_count
  defp safe_column_to_atom("rate_per_sec"), do: :rate_per_sec

  defp safe_column_to_atom(col),
    do: raise(ArgumentError, "unexpected column name from SQL query: #{col}")
end
