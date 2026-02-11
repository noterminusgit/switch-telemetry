defmodule SwitchTelemetry.MetricsTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Metrics

  defp build_metric(overrides \\ %{}) do
    Map.merge(
      %{
        time: DateTime.utc_now(),
        device_id: "dev_metrics_test",
        path: "/interfaces/counters/in-octets",
        source: :gnmi,
        value_float: 42.5,
        value_int: nil,
        value_str: nil
      },
      overrides
    )
  end

  describe "insert_batch/1" do
    test "inserts multiple metrics" do
      metrics = [
        build_metric(%{value_float: 10.0}),
        build_metric(%{value_float: 20.0, path: "/cpu/utilization"}),
        build_metric(%{value_float: 30.0, path: "/memory/used"})
      ]

      assert {3, nil} = Metrics.insert_batch(metrics)
    end

    test "inserts metrics with different value types" do
      metrics = [
        build_metric(%{value_float: 42.5, value_int: nil, value_str: nil}),
        build_metric(%{value_float: nil, value_int: 100, value_str: nil}),
        build_metric(%{value_float: nil, value_int: nil, value_str: "up"})
      ]

      assert {3, nil} = Metrics.insert_batch(metrics)
    end

    test "handles empty list" do
      assert {0, nil} = Metrics.insert_batch([])
    end

    test "defaults tags to empty map" do
      metrics = [build_metric() |> Map.delete(:tags)]
      assert {1, nil} = Metrics.insert_batch(metrics)
    end

    test "converts source to string" do
      metrics = [build_metric(%{source: :netconf})]
      assert {1, nil} = Metrics.insert_batch(metrics)
    end
  end

  describe "get_latest/2" do
    test "returns latest metrics for device ordered by time desc" do
      now = DateTime.utc_now()
      earlier = DateTime.add(now, -60, :second)

      Metrics.insert_batch([
        build_metric(%{time: earlier, value_float: 10.0}),
        build_metric(%{time: now, value_float: 20.0})
      ])

      results = Metrics.get_latest("dev_metrics_test")
      assert length(results) == 2
      # Most recent first
      assert hd(results).value_float == 20.0
    end

    test "respects limit option" do
      now = DateTime.utc_now()

      metrics =
        for i <- 1..5 do
          build_metric(%{time: DateTime.add(now, -i, :second), value_float: i * 1.0})
        end

      Metrics.insert_batch(metrics)

      results = Metrics.get_latest("dev_metrics_test", limit: 3)
      assert length(results) == 3
    end

    test "respects minutes option" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -60, :second)
      old = DateTime.add(now, -600, :second)

      Metrics.insert_batch([
        build_metric(%{time: recent, value_float: 1.0}),
        build_metric(%{time: old, value_float: 2.0})
      ])

      results = Metrics.get_latest("dev_metrics_test", minutes: 2)
      assert length(results) == 1
      assert hd(results).value_float == 1.0
    end

    test "returns empty list for unknown device" do
      assert Metrics.get_latest("nonexistent_device") == []
    end
  end

  describe "get_time_series/4" do
    test "returns time-bucketed aggregations" do
      now = DateTime.utc_now()
      t1 = DateTime.add(now, -120, :second)
      t2 = DateTime.add(now, -90, :second)
      t3 = DateTime.add(now, -60, :second)

      Metrics.insert_batch([
        build_metric(%{time: t1, device_id: "dev_ts", path: "/cpu", value_float: 10.0}),
        build_metric(%{time: t2, device_id: "dev_ts", path: "/cpu", value_float: 20.0}),
        build_metric(%{time: t3, device_id: "dev_ts", path: "/cpu", value_float: 30.0})
      ])

      time_range = %{start: DateTime.add(now, -300, :second), end: now}
      results = Metrics.get_time_series("dev_ts", "/cpu", "1 minute", time_range)

      assert is_list(results)
      assert length(results) >= 1
      # Each result should have the aggregation keys
      first = hd(results)
      assert Map.has_key?(first, :bucket)
      assert Map.has_key?(first, :avg_value)
      assert Map.has_key?(first, :max_value)
      assert Map.has_key?(first, :min_value)
      assert Map.has_key?(first, :sample_count)
    end

    test "returns empty list for no data" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -300, :second), end: now}
      results = Metrics.get_time_series("dev_none", "/cpu", "1 minute", time_range)
      assert results == []
    end

    test "raises on invalid bucket size" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -300, :second), end: now}

      assert_raise FunctionClauseError, fn ->
        Metrics.get_time_series("dev_test", "/cpu", "invalid", time_range)
      end
    end
  end
end
