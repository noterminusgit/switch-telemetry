defmodule SwitchTelemetry.Metrics.QueryRouterTest do
  use SwitchTelemetry.InfluxCase, async: false

  alias SwitchTelemetry.Metrics
  alias SwitchTelemetry.Metrics.QueryRouter

  defp build_metric(overrides) do
    Map.merge(
      %{
        time: DateTime.utc_now(),
        device_id: "dev_qr_test",
        path: "/test/counters",
        source: :gnmi,
        value_float: 42.5,
        value_int: nil,
        value_str: nil
      },
      overrides
    )
  end

  describe "query/3" do
    test "returns empty list for device with no data" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -3600, :second), end: now}

      result = QueryRouter.query("nonexistent_device", "/some/path", time_range)
      assert result == []
    end

    test "routes short ranges (< 1h) to raw data" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -1800, :second), end: now}

      result = QueryRouter.query("dev_test", "/test/path", time_range)
      assert is_list(result)
    end

    test "routes medium ranges (1h-24h)" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -7200, :second), end: now}

      result = QueryRouter.query("dev_test", "/test/path", time_range)
      assert is_list(result)
    end

    test "routes long ranges (>24h)" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -172_800, :second), end: now}

      result = QueryRouter.query("dev_test", "/test/path", time_range)
      assert is_list(result)
    end
  end

  describe "query_raw/4" do
    test "returns empty list when no data" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -3600, :second), end: now}

      result = QueryRouter.query_raw("dev_test", "/test/path", "1 minute", time_range)
      assert result == []
    end

    test "returns data when metrics exist" do
      now = DateTime.utc_now()

      Metrics.insert_batch([
        build_metric(%{time: now, value_float: 42.5})
      ])

      Process.sleep(500)

      time_range = %{start: DateTime.add(now, -60, :second), end: DateTime.add(now, 60, :second)}

      result = QueryRouter.query_raw("dev_qr_test", "/test/counters", "1 minute", time_range)
      assert length(result) >= 1
      assert hd(result).avg_value == 42.5
    end
  end

  describe "query_rate/4" do
    test "returns empty list when no data" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -3600, :second), end: now}

      result = QueryRouter.query_rate("dev_test", "/test/path", "1 minute", time_range)
      assert result == []
    end

    test "computes rate of change from value_int counters" do
      now = DateTime.utc_now()
      # Align to start of a minute so all points land in the same bucket
      minute_start =
        now
        |> DateTime.add(-120, :second)
        |> Map.put(:second, 0)
        |> Map.put(:microsecond, {0, 6})

      t1 = DateTime.add(minute_start, 10, :second)
      t2 = DateTime.add(minute_start, 20, :second)
      t3 = DateTime.add(minute_start, 30, :second)

      Metrics.insert_batch([
        build_metric(%{
          time: t1,
          device_id: "dev_rate_test",
          path: "/interfaces/counters/in-octets",
          value_float: nil,
          value_int: 1000
        }),
        build_metric(%{
          time: t2,
          device_id: "dev_rate_test",
          path: "/interfaces/counters/in-octets",
          value_float: nil,
          value_int: 2000
        }),
        build_metric(%{
          time: t3,
          device_id: "dev_rate_test",
          path: "/interfaces/counters/in-octets",
          value_float: nil,
          value_int: 3500
        })
      ])

      Process.sleep(500)

      time_range = %{start: minute_start, end: DateTime.add(minute_start, 60, :second)}

      result =
        QueryRouter.query_rate(
          "dev_rate_test",
          "/interfaces/counters/in-octets",
          "1 minute",
          time_range
        )

      assert length(result) == 1
      first = hd(result)
      assert Map.has_key?(first, :bucket)
      assert Map.has_key?(first, :rate_per_sec)
      # rate = (max - min) / interval_seconds = (3500 - 1000) / 60 = 41.67
      assert %Decimal{} = first.rate_per_sec
      assert Decimal.gt?(first.rate_per_sec, Decimal.new(0))
    end

    test "raises on invalid bucket size" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -60, :second), end: now}

      assert_raise FunctionClauseError, fn ->
        QueryRouter.query_rate("dev_test", "/path", "2 minutes", time_range)
      end
    end
  end

  describe "query/3 with data" do
    test "returns aggregated results for short time range with actual data" do
      now = DateTime.utc_now()
      t1 = DateTime.add(now, -120, :second)
      t2 = DateTime.add(now, -60, :second)

      Metrics.insert_batch([
        build_metric(%{
          time: t1,
          device_id: "dev_routing_test",
          path: "/cpu/utilization",
          value_float: 55.0
        }),
        build_metric(%{
          time: t2,
          device_id: "dev_routing_test",
          path: "/cpu/utilization",
          value_float: 65.0
        })
      ])

      Process.sleep(500)

      # Short range (< 1h) routes to raw data
      time_range = %{start: DateTime.add(now, -300, :second), end: now}
      result = QueryRouter.query("dev_routing_test", "/cpu/utilization", time_range)

      assert is_list(result)
      assert length(result) >= 1

      first = hd(result)
      assert Map.has_key?(first, :bucket)
      assert Map.has_key?(first, :avg_value)
      assert Map.has_key?(first, :sample_count)
    end

    test "filters results by device_id and path correctly" do
      now = DateTime.utc_now()
      t1 = DateTime.add(now, -30, :second)

      Metrics.insert_batch([
        build_metric(%{time: t1, device_id: "dev_filter_a", path: "/cpu", value_float: 10.0}),
        build_metric(%{time: t1, device_id: "dev_filter_b", path: "/cpu", value_float: 90.0})
      ])

      Process.sleep(500)

      time_range = %{start: DateTime.add(now, -60, :second), end: now}

      result_a = QueryRouter.query("dev_filter_a", "/cpu", time_range)
      result_b = QueryRouter.query("dev_filter_b", "/cpu", time_range)

      assert length(result_a) == 1
      assert length(result_b) == 1
      assert hd(result_a).avg_value == 10.0
      assert hd(result_b).avg_value == 90.0
    end
  end
end
