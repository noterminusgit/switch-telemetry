defmodule SwitchTelemetry.Alerting.EvaluatorPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SwitchTelemetry.Alerting.Evaluator

  # ---------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------

  defp condition_gen do
    member_of([:above, :below, :absent, :rate_increase])
  end

  defp rule_gen(overrides \\ %{}) do
    gen all(
          name <- string(:alphanumeric, min_length: 1, max_length: 30),
          path <- string(:alphanumeric, min_length: 1, max_length: 50),
          threshold <- float(min: -1_000_000.0, max: 1_000_000.0),
          condition <- condition_gen()
        ) do
      Map.merge(
        %{
          name: name,
          path: "/metrics/#{path}",
          condition: condition,
          threshold: threshold,
          state: :ok,
          last_fired_at: nil,
          cooldown_seconds: 300,
          duration_seconds: 60
        },
        overrides
      )
    end
  end

  # ---------------------------------------------------------------
  # check_condition/3 — :above
  # ---------------------------------------------------------------
  describe "check_condition :above property" do
    property "fires iff value > threshold for all float pairs" do
      check all(
              value <- float(min: -1_000_000.0, max: 1_000_000.0),
              threshold <- float(min: -1_000_000.0, max: 1_000_000.0)
            ) do
        result = Evaluator.check_condition(:above, value, threshold)

        if value > threshold do
          assert {:firing, ^value} = result
        else
          assert :ok = result
        end
      end
    end

    property "nil value always returns :ok" do
      check all(threshold <- float(min: -1_000_000.0, max: 1_000_000.0)) do
        assert :ok = Evaluator.check_condition(:above, nil, threshold)
      end
    end
  end

  # ---------------------------------------------------------------
  # check_condition/3 — :below
  # ---------------------------------------------------------------
  describe "check_condition :below property" do
    property "fires iff value < threshold for all float pairs" do
      check all(
              value <- float(min: -1_000_000.0, max: 1_000_000.0),
              threshold <- float(min: -1_000_000.0, max: 1_000_000.0)
            ) do
        result = Evaluator.check_condition(:below, value, threshold)

        if value < threshold do
          assert {:firing, ^value} = result
        else
          assert :ok = result
        end
      end
    end

    property "nil value always returns :ok" do
      check all(threshold <- float(min: -1_000_000.0, max: 1_000_000.0)) do
        assert :ok = Evaluator.check_condition(:below, nil, threshold)
      end
    end
  end

  # ---------------------------------------------------------------
  # build_message/2
  # ---------------------------------------------------------------
  describe "build_message/2 property" do
    property "always returns a binary for any condition and value" do
      check all(
              rule <- rule_gen(),
              value <- one_of([float(min: -1_000_000.0, max: 1_000_000.0), constant(nil)])
            ) do
        message = Evaluator.build_message(rule, value)
        assert is_binary(message)
        assert String.length(message) > 0
      end
    end

    property "message contains the rule name" do
      check all(rule <- rule_gen()) do
        message = Evaluator.build_message(rule, 42.0)
        assert String.contains?(message, rule.name)
      end
    end

    property "message contains the rule path" do
      check all(rule <- rule_gen()) do
        message = Evaluator.build_message(rule, 42.0)
        assert String.contains?(message, rule.path)
      end
    end
  end

  # ---------------------------------------------------------------
  # calculate_rate/2
  # ---------------------------------------------------------------
  describe "calculate_rate/2 property" do
    property "sign matches direction of change when elapsed > 0" do
      check all(
              v1 <- float(min: -100_000.0, max: 100_000.0),
              v2 <- float(min: -100_000.0, max: 100_000.0),
              elapsed <- integer(1..10_000)
            ) do
        now = DateTime.utc_now()
        earlier = DateTime.add(now, -elapsed, :second)

        metrics = [
          %{value_float: v1, time: now},
          %{value_float: v2, time: earlier}
        ]

        rate = Evaluator.calculate_rate(metrics, 60)

        cond do
          v1 > v2 -> assert rate > 0
          v1 < v2 -> assert rate < 0
          v1 == v2 -> assert rate == 0.0
        end
      end
    end

    property "returns nil for fewer than 2 data points" do
      check all(value <- float(min: -1000.0, max: 1000.0)) do
        assert Evaluator.calculate_rate([], 60) == nil

        single = [%{value_float: value, time: DateTime.utc_now()}]
        assert Evaluator.calculate_rate(single, 60) == nil
      end
    end

    property "returns nil when elapsed time is zero" do
      check all(
              v1 <- float(min: -1000.0, max: 1000.0),
              v2 <- float(min: -1000.0, max: 1000.0)
            ) do
        now = DateTime.utc_now()

        metrics = [
          %{value_float: v1, time: now},
          %{value_float: v2, time: now}
        ]

        assert Evaluator.calculate_rate(metrics, 60) == nil
      end
    end
  end

  # ---------------------------------------------------------------
  # extract_value/1
  # ---------------------------------------------------------------
  describe "extract_value/1 property" do
    property "never crashes on a list of maps with value_float" do
      check all(
              values <-
                list_of(
                  map_of(
                    constant(:value_float),
                    one_of([float(min: -1000.0, max: 1000.0), constant(nil)]),
                    min_length: 1,
                    max_length: 1
                  ),
                  min_length: 0,
                  max_length: 20
                )
            ) do
        result = Evaluator.extract_value(values)

        case values do
          [] -> assert result == nil
          [first | _] -> assert result == first.value_float
        end
      end
    end

    property "returns nil for empty list" do
      assert Evaluator.extract_value([]) == nil
    end
  end
end
