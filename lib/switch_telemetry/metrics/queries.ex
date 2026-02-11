defmodule SwitchTelemetry.Metrics.Queries do
  @moduledoc """
  TimescaleDB-specific queries for metrics data.
  Uses time_bucket and other hyperfunctions.
  """
  import Ecto.Query

  alias SwitchTelemetry.Repo

  @valid_bucket_sizes ["10 seconds", "30 seconds", "1 minute", "5 minutes", "15 minutes", "1 hour"]

  @doc """
  Get the most recent metrics for a device.
  """
  def get_latest(device_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    minutes = Keyword.get(opts, :minutes, 5)

    from(m in "metrics",
      where: m.device_id == ^device_id,
      where: m.time > ago(^minutes, "minute"),
      order_by: [desc: m.time],
      limit: ^limit,
      select: %{
        time: m.time,
        path: m.path,
        source: m.source,
        value_float: m.value_float,
        value_int: m.value_int,
        value_str: m.value_str,
        tags: m.tags
      }
    )
    |> Repo.all()
  end

  @doc """
  Get time-bucketed aggregation for a device and path.
  `bucket_size` is a PostgreSQL interval string like "1 minute", "5 minutes", "1 hour".
  `time_range` is a map with `:start` and `:end` DateTime keys.
  """
  def get_time_series(device_id, path, bucket_size, time_range)
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

  defp safe_column_to_atom(col),
    do: raise(ArgumentError, "unexpected column name from SQL query: #{col}")
end
