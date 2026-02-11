defmodule SwitchTelemetry.Alerting.EvaluatorTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Alerting.Evaluator

  # Helper to build a rule map with sensible defaults
  defp build_rule(overrides) do
    Map.merge(
      %{
        name: "CPU Alert",
        path: "/system/cpu/utilization",
        condition: :above,
        threshold: 90.0,
        state: :ok,
        last_fired_at: nil,
        cooldown_seconds: 300,
        duration_seconds: 60
      },
      overrides
    )
  end

  defp build_metric(value_float, time) do
    %{value_float: value_float, time: time}
  end

  # ---------------------------------------------------------------
  # check_condition/3
  # ---------------------------------------------------------------
  describe "check_condition/3" do
    test ":above fires when value exceeds threshold" do
      assert {:firing, 95.0} = Evaluator.check_condition(:above, 95.0, 90.0)
    end

    test ":above returns :ok when value equals threshold" do
      assert :ok = Evaluator.check_condition(:above, 90.0, 90.0)
    end

    test ":above returns :ok when value is below threshold" do
      assert :ok = Evaluator.check_condition(:above, 85.0, 90.0)
    end

    test ":above returns :ok when value is nil" do
      assert :ok = Evaluator.check_condition(:above, nil, 90.0)
    end

    test ":below fires when value is under threshold" do
      assert {:firing, 5.0} = Evaluator.check_condition(:below, 5.0, 10.0)
    end

    test ":below returns :ok when value equals threshold" do
      assert :ok = Evaluator.check_condition(:below, 10.0, 10.0)
    end

    test ":below returns :ok when value is above threshold" do
      assert :ok = Evaluator.check_condition(:below, 15.0, 10.0)
    end

    test ":below returns :ok when value is nil" do
      assert :ok = Evaluator.check_condition(:below, nil, 10.0)
    end

    test ":absent fires when value is nil" do
      assert {:firing, nil} = Evaluator.check_condition(:absent, nil, nil)
    end

    test ":absent returns :ok when value is present" do
      assert :ok = Evaluator.check_condition(:absent, 42.0, nil)
    end

    test ":rate_increase fires when rate exceeds threshold" do
      assert {:firing, 5.5} = Evaluator.check_condition(:rate_increase, 5.5, 3.0)
    end

    test ":rate_increase returns :ok when rate equals threshold" do
      assert :ok = Evaluator.check_condition(:rate_increase, 3.0, 3.0)
    end

    test ":rate_increase returns :ok when rate is below threshold" do
      assert :ok = Evaluator.check_condition(:rate_increase, 1.0, 3.0)
    end

    test ":rate_increase returns :ok when rate is nil" do
      assert :ok = Evaluator.check_condition(:rate_increase, nil, 3.0)
    end
  end

  # ---------------------------------------------------------------
  # should_fire?/2
  # ---------------------------------------------------------------
  describe "should_fire?/2" do
    test "returns true when last_fired_at is nil" do
      rule = build_rule(%{last_fired_at: nil, cooldown_seconds: 300})
      assert Evaluator.should_fire?(rule, DateTime.utc_now())
    end

    test "returns false when within cooldown period" do
      now = DateTime.utc_now()
      last_fired = DateTime.add(now, -100, :second)
      rule = build_rule(%{last_fired_at: last_fired, cooldown_seconds: 300})

      refute Evaluator.should_fire?(rule, now)
    end

    test "returns true when cooldown has elapsed" do
      now = DateTime.utc_now()
      last_fired = DateTime.add(now, -600, :second)
      rule = build_rule(%{last_fired_at: last_fired, cooldown_seconds: 300})

      assert Evaluator.should_fire?(rule, now)
    end

    test "returns true when exactly at cooldown boundary" do
      now = DateTime.utc_now()
      last_fired = DateTime.add(now, -300, :second)
      rule = build_rule(%{last_fired_at: last_fired, cooldown_seconds: 300})

      assert Evaluator.should_fire?(rule, now)
    end
  end

  # ---------------------------------------------------------------
  # build_message/2
  # ---------------------------------------------------------------
  describe "build_message/2" do
    test ":above condition message" do
      rule = build_rule(%{condition: :above, threshold: 90.0})
      msg = Evaluator.build_message(rule, 95.0)

      assert msg == "CPU Alert: value 95.0 exceeds threshold 90.0 on path /system/cpu/utilization"
    end

    test ":below condition message" do
      rule = build_rule(%{condition: :below, threshold: 10.0})
      msg = Evaluator.build_message(rule, 5.0)

      assert msg == "CPU Alert: value 5.0 below threshold 10.0 on path /system/cpu/utilization"
    end

    test ":absent condition message" do
      rule = build_rule(%{condition: :absent})
      msg = Evaluator.build_message(rule, nil)

      assert msg == "CPU Alert: no data received on path /system/cpu/utilization"
    end

    test ":rate_increase condition message" do
      rule = build_rule(%{condition: :rate_increase, threshold: 3.0})
      msg = Evaluator.build_message(rule, 5.5)

      assert msg ==
               "CPU Alert: rate of change 5.5/s exceeds threshold 3.0/s on path /system/cpu/utilization"
    end
  end

  # ---------------------------------------------------------------
  # extract_value/1
  # ---------------------------------------------------------------
  describe "extract_value/1" do
    test "returns nil for empty list" do
      assert Evaluator.extract_value([]) == nil
    end

    test "returns the first element's value_float" do
      now = DateTime.utc_now()

      metrics = [
        build_metric(95.5, now),
        build_metric(90.0, DateTime.add(now, -60, :second))
      ]

      assert Evaluator.extract_value(metrics) == 95.5
    end

    test "returns value_float even for single-element list" do
      assert Evaluator.extract_value([build_metric(42.0, DateTime.utc_now())]) == 42.0
    end
  end

  # ---------------------------------------------------------------
  # calculate_rate/2
  # ---------------------------------------------------------------
  describe "calculate_rate/2" do
    test "returns nil for fewer than 2 data points" do
      assert Evaluator.calculate_rate([], 60) == nil
      assert Evaluator.calculate_rate([build_metric(10.0, DateTime.utc_now())], 60) == nil
    end

    test "calculates rate correctly with two points" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -10, :second)

      metrics = [
        build_metric(100.0, now),
        build_metric(50.0, earlier)
      ]

      # (100 - 50) / 10 = 5.0
      assert Evaluator.calculate_rate(metrics, 60) == 5.0
    end

    test "calculates negative rate" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -20, :second)

      metrics = [
        build_metric(30.0, now),
        build_metric(50.0, earlier)
      ]

      # (30 - 50) / 20 = -1.0
      assert Evaluator.calculate_rate(metrics, 60) == -1.0
    end

    test "returns nil when elapsed time is zero" do
      now = DateTime.utc_now()

      metrics = [
        build_metric(100.0, now),
        build_metric(50.0, now)
      ]

      assert Evaluator.calculate_rate(metrics, 60) == nil
    end
  end

  # ---------------------------------------------------------------
  # evaluate_rule/2 — full lifecycle
  # ---------------------------------------------------------------
  describe "evaluate_rule/2" do
    test "rule in :ok state with metrics above threshold transitions to firing" do
      now = DateTime.utc_now()
      rule = build_rule(%{condition: :above, threshold: 90.0, state: :ok})
      metrics = [build_metric(95.0, now)]

      assert {:firing, 95.0, message} = Evaluator.evaluate_rule(rule, metrics)
      assert message =~ "exceeds threshold"
    end

    test "rule in :ok state with metrics below threshold stays :ok" do
      now = DateTime.utc_now()
      rule = build_rule(%{condition: :above, threshold: 90.0, state: :ok})
      metrics = [build_metric(85.0, now)]

      assert :ok = Evaluator.evaluate_rule(rule, metrics)
    end

    test "rule already :firing with metrics still above threshold returns :ok (no duplicate)" do
      now = DateTime.utc_now()
      rule = build_rule(%{condition: :above, threshold: 90.0, state: :firing})
      metrics = [build_metric(95.0, now)]

      assert :ok = Evaluator.evaluate_rule(rule, metrics)
    end

    test "rule in :firing state with metrics below threshold transitions to resolved" do
      now = DateTime.utc_now()
      rule = build_rule(%{condition: :above, threshold: 90.0, state: :firing})
      metrics = [build_metric(85.0, now)]

      assert {:resolved, message} = Evaluator.evaluate_rule(rule, metrics)
      assert message =~ "resolved"
    end

    test "rule in :ok state with cooldown active returns :ok" do
      now = DateTime.utc_now()
      last_fired = DateTime.add(now, -100, :second)

      rule =
        build_rule(%{
          condition: :above,
          threshold: 90.0,
          state: :ok,
          last_fired_at: last_fired,
          cooldown_seconds: 300
        })

      metrics = [build_metric(95.0, now)]

      assert :ok = Evaluator.evaluate_rule(rule, metrics)
    end

    test ":absent condition with empty metrics fires" do
      rule = build_rule(%{condition: :absent, state: :ok})
      metrics = []

      assert {:firing, nil, message} = Evaluator.evaluate_rule(rule, metrics)
      assert message =~ "no data received"
    end

    test ":absent condition with data present stays :ok" do
      now = DateTime.utc_now()
      rule = build_rule(%{condition: :absent, state: :ok})
      metrics = [build_metric(42.0, now)]

      assert :ok = Evaluator.evaluate_rule(rule, metrics)
    end

    test ":rate_increase fires when rate exceeds threshold" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -10, :second)

      rule =
        build_rule(%{
          condition: :rate_increase,
          threshold: 3.0,
          state: :ok,
          duration_seconds: 60
        })

      metrics = [
        build_metric(100.0, now),
        build_metric(50.0, earlier)
      ]

      # rate = (100 - 50) / 10 = 5.0 > 3.0
      assert {:firing, 5.0, message} = Evaluator.evaluate_rule(rule, metrics)
      assert message =~ "rate of change"
    end

    test ":below condition fires when value is under threshold" do
      now = DateTime.utc_now()

      rule =
        build_rule(%{
          condition: :below,
          threshold: 10.0,
          state: :ok
        })

      metrics = [build_metric(5.0, now)]

      assert {:firing, 5.0, message} = Evaluator.evaluate_rule(rule, metrics)
      assert message =~ "below threshold"
    end

    test "resolved message for :firing rule that recovers from :absent" do
      rule = build_rule(%{condition: :absent, state: :firing})
      now = DateTime.utc_now()
      metrics = [build_metric(42.0, now)]

      assert {:resolved, message} = Evaluator.evaluate_rule(rule, metrics)
      assert message =~ "resolved"
    end
  end
end
