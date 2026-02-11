defmodule SwitchTelemetry.Metrics do
  @moduledoc """
  Context for telemetry metrics ingestion and retrieval.
  """
  alias SwitchTelemetry.Repo
  alias SwitchTelemetry.Metrics.Queries

  defdelegate get_latest(device_id, opts \\ []), to: Queries
  defdelegate get_time_series(device_id, path, bucket_size, time_range), to: Queries

  @doc """
  Insert a batch of metric data points.
  Expects a list of maps with keys: time, device_id, path, source, tags, value_float, value_int, value_str.
  """
  def insert_batch(metrics) when is_list(metrics) do
    entries =
      Enum.map(metrics, fn m ->
        %{
          time: m.time,
          device_id: m.device_id,
          path: m.path,
          source: to_string(m.source),
          tags: m[:tags] || %{},
          value_float: m[:value_float],
          value_int: m[:value_int],
          value_str: m[:value_str]
        }
      end)

    Repo.insert_all("metrics", entries)
  end
end
