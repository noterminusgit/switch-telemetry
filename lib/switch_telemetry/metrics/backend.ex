defmodule SwitchTelemetry.Metrics.Backend do
  @moduledoc """
  Behaviour for metrics storage backends.
  """

  @type metric :: map()
  @type time_range :: %{start: DateTime.t(), end: DateTime.t()}

  @callback insert_batch([metric()]) :: {non_neg_integer(), nil}
  @callback get_latest(String.t(), keyword()) :: [map()]
  @callback query(String.t(), String.t(), time_range()) :: [map()]
  @callback query_raw(String.t(), String.t(), String.t(), time_range()) :: [map()]
  @callback query_rate(String.t(), String.t(), String.t(), time_range()) :: [map()]
end
