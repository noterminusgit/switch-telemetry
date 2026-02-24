defmodule SwitchTelemetry.Metrics.InfluxBackend do
  @moduledoc """
  InfluxDB v2 implementation of the metrics storage backend.
  Uses Flux queries for reads and line protocol for writes.
  """

  @behaviour SwitchTelemetry.Metrics.Backend

  require Logger

  alias SwitchTelemetry.InfluxDB
  alias SwitchTelemetry.Metrics.Backend

  @valid_bucket_sizes [
    "10 seconds",
    "30 seconds",
    "1 minute",
    "5 minutes",
    "15 minutes",
    "1 hour"
  ]

  @impl true
  @spec insert_batch([map()]) :: {non_neg_integer(), nil}
  def insert_batch([]), do: {0, nil}

  def insert_batch(metrics) when is_list(metrics) do
    points =
      Enum.map(metrics, fn m ->
        fields =
          %{}
          |> maybe_put("value_float", m[:value_float])
          |> maybe_put("value_int", m[:value_int])
          |> maybe_put("value_str", m[:value_str])

        # Ensure at least one field exists (InfluxDB requires it)
        fields = if map_size(fields) == 0, do: %{"value_float" => 0.0}, else: fields

        %{
          measurement: "metrics",
          tags: %{
            device_id: to_string(m.device_id),
            path: to_string(m.path),
            source: to_string(m.source)
          },
          fields: fields,
          timestamp: datetime_to_nanoseconds(m.time)
        }
      end)

    case InfluxDB.write(points) do
      :ok ->
        :ok

      other ->
        Logger.error("InfluxDB write failed for #{length(metrics)} points: #{inspect(other)}")
    end

    {length(metrics), nil}
  end

  @impl true
  @spec get_latest(String.t(), keyword()) :: [map()]
  def get_latest(device_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    minutes = Keyword.get(opts, :minutes, 5)
    bucket = influx_config(:bucket)

    flux = """
    from(bucket: "#{bucket}")
      |> range(start: -#{minutes}m)
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> pivot(rowKey: ["_time", "path", "source"], columnKey: ["_field"], valueColumn: "_value")
      |> sort(columns: ["_time"], desc: true)
      |> limit(n: #{limit})
    """

    case InfluxDB.query(flux) do
      rows when is_list(rows) ->
        rows |> List.flatten() |> Enum.map(&normalize_metric/1)

      other ->
        Logger.error(
          "InfluxDB get_latest query failed for device #{device_id}: #{inspect(other)}"
        )

        []
    end
  end

  @impl true
  @spec query(String.t(), String.t(), Backend.time_range()) :: [map()]
  def query(device_id, path, time_range) do
    duration_seconds = DateTime.diff(time_range.end, time_range.start)

    cond do
      duration_seconds <= 3_600 ->
        query_raw(device_id, path, "10 seconds", time_range)

      duration_seconds <= 86_400 ->
        query_bucket("metrics_5m", device_id, path, "5m", time_range)

      true ->
        query_bucket("metrics_1h", device_id, path, "1h", time_range)
    end
  end

  @impl true
  @spec query_raw(String.t(), String.t(), String.t(), Backend.time_range()) :: [map()]
  def query_raw(device_id, path, bucket_size, time_range)
      when bucket_size in @valid_bucket_sizes do
    bucket = influx_config(:bucket)
    flux_duration = pg_interval_to_flux(bucket_size)

    flux = """
    from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> filter(fn: (r) => r._field == "value_float")
      |> aggregateWindow(every: #{flux_duration}, fn: mean, createEmpty: false)
      |> yield(name: "mean")

    from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> filter(fn: (r) => r._field == "value_float")
      |> aggregateWindow(every: #{flux_duration}, fn: max, createEmpty: false)
      |> yield(name: "max")

    from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> filter(fn: (r) => r._field == "value_float")
      |> aggregateWindow(every: #{flux_duration}, fn: count, createEmpty: false)
      |> yield(name: "count")

    from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> filter(fn: (r) => r._field == "value_float")
      |> aggregateWindow(every: #{flux_duration}, fn: min, createEmpty: false)
      |> yield(name: "min")
    """

    case InfluxDB.query(flux) do
      rows when is_list(rows) ->
        normalize_aggregates(rows)

      other ->
        Logger.error("InfluxDB query_raw failed for #{device_id}/#{path}: #{inspect(other)}")
        log_influx_config()
        []
    end
  end

  @impl true
  @spec query_rate(String.t(), String.t(), String.t(), Backend.time_range()) :: [map()]
  def query_rate(device_id, path, bucket_size, time_range)
      when bucket_size in @valid_bucket_sizes do
    bucket = influx_config(:bucket)
    flux_duration = pg_interval_to_flux(bucket_size)
    interval_seconds = pg_interval_to_seconds(bucket_size)

    flux = """
    max_data = from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> filter(fn: (r) => r._field == "value_int")
      |> aggregateWindow(every: #{flux_duration}, fn: max, createEmpty: false)

    min_data = from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> filter(fn: (r) => r._field == "value_int")
      |> aggregateWindow(every: #{flux_duration}, fn: min, createEmpty: false)

    join(tables: {max: max_data, min: min_data}, on: ["_time", "device_id", "path"])
      |> map(fn: (r) => ({r with _value: float(v: r._value_max - r._value_min) / #{interval_seconds}.0}))
      |> yield(name: "rate")
    """

    case InfluxDB.query(flux) do
      rows when is_list(rows) ->
        rows |> List.flatten() |> Enum.map(&normalize_rate/1)

      other ->
        Logger.error("InfluxDB query_rate failed for #{device_id}/#{path}: #{inspect(other)}")
        []
    end
  end

  @doc """
  Query metrics where the path starts with the given prefix.
  Returns results grouped by full path, each with :path and :data keys.
  Useful for subscription paths which are prefixes of stored metric paths.
  """
  @spec query_by_prefix(String.t(), String.t(), Backend.time_range()) :: [map()]
  def query_by_prefix(device_id, path_prefix, time_range) do
    bucket = influx_config(:bucket)
    duration_seconds = DateTime.diff(time_range.end, time_range.start)

    flux_duration =
      cond do
        duration_seconds <= 3_600 -> "10s"
        duration_seconds <= 86_400 -> "5m"
        true -> "1h"
      end

    flux = """
    import "strings"

    from(bucket: "#{bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => strings.hasPrefix(v: r.path, prefix: "#{escape_flux(path_prefix)}"))
      |> filter(fn: (r) => r._field == "value_float")
      |> aggregateWindow(every: #{flux_duration}, fn: mean, createEmpty: false)
    """

    case InfluxDB.query(flux) do
      rows when is_list(rows) ->
        rows
        |> List.flatten()
        |> Enum.group_by(fn row -> row["path"] end)
        |> Enum.map(fn {path, path_rows} ->
          data =
            Enum.map(path_rows, fn row ->
              %{bucket: parse_influx_time(row["_time"]), avg_value: row["_value"]}
            end)

          %{path: path, data: data}
        end)

      other ->
        Logger.error(
          "InfluxDB query_by_prefix failed for #{device_id}/#{path_prefix}: #{inspect(other)}"
        )

        []
    end
  end

  # Query a downsampled bucket (metrics_5m, metrics_1h)
  defp query_bucket(ds_bucket, device_id, path, flux_duration, time_range) do
    flux = """
    from(bucket: "#{ds_bucket}")
      |> range(start: #{format_time(time_range.start)}, stop: #{format_time(time_range.end)})
      |> filter(fn: (r) => r._measurement == "metrics")
      |> filter(fn: (r) => r.device_id == "#{escape_flux(device_id)}")
      |> filter(fn: (r) => r.path == "#{escape_flux(path)}")
      |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
      |> sort(columns: ["_time"])
    """

    case InfluxDB.query(flux) do
      rows when is_list(rows) and rows != [] ->
        Enum.map(rows, fn row ->
          %{
            bucket: parse_influx_time(row["_time"]),
            avg_value: row["avg_value"],
            max_value: row["max_value"],
            min_value: row["min_value"],
            sample_count: row["sample_count"]
          }
        end)

      _ ->
        # Fall back to raw bucket with aggregation
        query_raw(device_id, path, flux_to_pg_interval(flux_duration), time_range)
    end
  end

  # Normalize a single metric row from Flux pivot result
  defp normalize_metric(row) do
    %{
      time: parse_influx_time(row["_time"]),
      path: row["path"],
      source: row["source"],
      value_float: row["value_float"],
      value_int: row["value_int"],
      value_str: row["value_str"],
      tags: %{}
    }
  end

  # Combine parallel aggregate results into unified rows
  # Multi-yield Flux queries return a list of lists (one per yield)
  defp normalize_aggregates(rows) do
    flat_rows = List.flatten(rows)
    grouped = Enum.group_by(flat_rows, fn row -> row["result"] end)

    mean_rows = Map.get(grouped, "mean", [])
    max_rows = Map.get(grouped, "max", [])
    min_rows = Map.get(grouped, "min", [])
    count_rows = Map.get(grouped, "count", [])

    # Index by time for joining
    max_by_time = index_by_time(max_rows)
    min_by_time = index_by_time(min_rows)
    count_by_time = index_by_time(count_rows)

    Enum.map(mean_rows, fn row ->
      time = row["_time"]

      %{
        bucket: parse_influx_time(time),
        avg_value: row["_value"],
        max_value: get_in(max_by_time, [time, "_value"]),
        min_value: get_in(min_by_time, [time, "_value"]),
        sample_count: get_in(count_by_time, [time, "_value"])
      }
    end)
  end

  defp index_by_time(rows) do
    Map.new(rows, fn row -> {row["_time"], row} end)
  end

  # Normalize a rate result row
  defp normalize_rate(row) do
    rate = row["_value"] || 0.0

    %{
      bucket: parse_influx_time(row["_time"]),
      rate_per_sec: Decimal.from_float(rate / 1.0)
    }
  end

  # Convert PostgreSQL interval strings to Flux durations
  defp pg_interval_to_flux("10 seconds"), do: "10s"
  defp pg_interval_to_flux("30 seconds"), do: "30s"
  defp pg_interval_to_flux("1 minute"), do: "1m"
  defp pg_interval_to_flux("5 minutes"), do: "5m"
  defp pg_interval_to_flux("15 minutes"), do: "15m"
  defp pg_interval_to_flux("1 hour"), do: "1h"

  # Convert PostgreSQL interval strings to seconds
  defp pg_interval_to_seconds("10 seconds"), do: 10
  defp pg_interval_to_seconds("30 seconds"), do: 30
  defp pg_interval_to_seconds("1 minute"), do: 60
  defp pg_interval_to_seconds("5 minutes"), do: 300
  defp pg_interval_to_seconds("15 minutes"), do: 900
  defp pg_interval_to_seconds("1 hour"), do: 3600

  # Convert Flux duration back to PG interval (for fallback)
  defp flux_to_pg_interval("5m"), do: "5 minutes"
  defp flux_to_pg_interval("1h"), do: "1 hour"

  defp format_time(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse_influx_time(nil), do: nil

  defp parse_influx_time(ts) when is_integer(ts) do
    ts
    |> div(1_000_000_000)
    |> DateTime.from_unix!()
  end

  defp parse_influx_time(time_str) when is_binary(time_str) do
    case DateTime.from_iso8601(time_str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_influx_time(%DateTime{} = dt), do: dt

  defp datetime_to_nanoseconds(%DateTime{} = dt) do
    DateTime.to_unix(dt, :nanosecond)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp escape_flux(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end

  defp influx_config(key) do
    Application.get_env(:switch_telemetry, SwitchTelemetry.InfluxDB)
    |> Keyword.fetch!(key)
  end

  defp log_influx_config do
    config = Application.get_env(:switch_telemetry, SwitchTelemetry.InfluxDB, [])
    token = get_in(config, [:auth, :token]) || "nil"
    redacted = String.slice(token, 0, 6) <> "..." <> String.slice(token, -4, 4)

    Logger.error(
      "InfluxDB config: host=#{config[:host]}:#{config[:port]} " <>
        "org=#{config[:org]} bucket=#{config[:bucket]} token=#{redacted}"
    )
  end
end
