defmodule SwitchTelemetry.Alerting.Evaluator do
  @moduledoc """
  Pure functions for evaluating alert rules against metric data.

  No database access or side effects — all inputs and outputs are plain
  data structures. This module is the core decision engine for the alerting
  pipeline.
  """

  @doc """
  Check whether a single metric value satisfies a condition against a threshold.

  Returns `{:firing, value}` when the condition is met, `:ok` otherwise.
  """
  @spec check_condition(atom(), number() | nil, number() | nil) ::
          {:firing, number() | nil} | :ok
  def check_condition(:above, nil, _threshold), do: :ok
  def check_condition(:above, value, threshold) when value > threshold, do: {:firing, value}
  def check_condition(:above, _value, _threshold), do: :ok

  def check_condition(:below, nil, _threshold), do: :ok
  def check_condition(:below, value, threshold) when value < threshold, do: {:firing, value}
  def check_condition(:below, _value, _threshold), do: :ok

  def check_condition(:absent, nil, _threshold), do: {:firing, nil}
  def check_condition(:absent, _value, _threshold), do: :ok

  def check_condition(:rate_increase, nil, _threshold), do: :ok

  def check_condition(:rate_increase, rate, threshold) when rate > threshold,
    do: {:firing, rate}

  def check_condition(:rate_increase, _rate, _threshold), do: :ok

  @doc """
  Determine whether a rule is allowed to fire based on its cooldown period.

  Returns `true` if the rule has never fired or the cooldown has elapsed,
  `false` if still within the cooldown window.
  """
  @spec should_fire?(map(), DateTime.t()) :: boolean()
  def should_fire?(%{last_fired_at: nil}, _current_time), do: true

  def should_fire?(
        %{last_fired_at: last_fired_at, cooldown_seconds: cooldown_seconds},
        current_time
      ) do
    DateTime.diff(current_time, last_fired_at, :second) >= cooldown_seconds
  end

  @doc """
  Build a human-readable alert message for a given rule and metric value.
  """
  @spec build_message(map(), number() | nil) :: String.t()
  def build_message(%{condition: :above} = rule, value) do
    "#{rule.name}: value #{value} exceeds threshold #{rule.threshold} on path #{rule.path}"
  end

  def build_message(%{condition: :below} = rule, value) do
    "#{rule.name}: value #{value} below threshold #{rule.threshold} on path #{rule.path}"
  end

  def build_message(%{condition: :absent} = rule, _value) do
    "#{rule.name}: no data received on path #{rule.path}"
  end

  def build_message(%{condition: :rate_increase} = rule, value) do
    "#{rule.name}: rate of change #{value}/s exceeds threshold #{rule.threshold}/s on path #{rule.path}"
  end

  @doc """
  Extract the latest value_float from a list of metric maps ordered descending
  by time. Returns `nil` if the list is empty.
  """
  @spec extract_value([map()]) :: number() | nil
  def extract_value([]), do: nil
  def extract_value([latest | _rest]), do: latest.value_float

  @doc """
  Calculate the rate of change (per second) across a list of metric maps.

  Expects metrics ordered descending by time (newest first). Returns `nil`
  if fewer than 2 data points or if the elapsed time is zero.
  """
  @spec calculate_rate([map()], integer()) :: number() | nil
  def calculate_rate(metrics, _duration_seconds) when length(metrics) < 2, do: nil

  def calculate_rate(metrics, _duration_seconds) do
    newest = List.first(metrics)
    oldest = List.last(metrics)
    elapsed = DateTime.diff(newest.time, oldest.time, :second)

    if elapsed == 0 do
      nil
    else
      (newest.value_float - oldest.value_float) / elapsed
    end
  end

  @doc """
  Evaluate a rule against a set of metrics. Orchestrates value extraction,
  condition checking, cooldown enforcement, and state transitions.

  Returns:
    - `{:firing, value, message}` when transitioning from `:ok` to firing
    - `{:resolved, message}` when transitioning from `:firing` to resolved
    - `:ok` when no state change is needed
  """
  @spec evaluate_rule(map(), [map()]) ::
          {:firing, number() | nil, String.t()} | {:resolved, String.t()} | :ok
  def evaluate_rule(rule, metrics) do
    value =
      case rule.condition do
        :rate_increase -> calculate_rate(metrics, rule.duration_seconds)
        _ -> extract_value(metrics)
      end

    case check_condition(rule.condition, value, rule.threshold) do
      {:firing, firing_value} ->
        cond do
          rule.state == :firing ->
            :ok

          not should_fire?(rule, DateTime.utc_now()) ->
            :ok

          true ->
            {:firing, firing_value, build_message(rule, firing_value)}
        end

      :ok ->
        if rule.state == :firing do
          {:resolved, "#{rule.name}: resolved on path #{rule.path}"}
        else
          :ok
        end
    end
  end
end
