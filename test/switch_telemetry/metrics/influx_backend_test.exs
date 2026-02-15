defmodule SwitchTelemetry.Metrics.InfluxBackendTest do
  use SwitchTelemetry.InfluxCase, async: false

  alias SwitchTelemetry.Metrics.InfluxBackend

  defp build_metric(overrides) do
    Map.merge(
      %{
        time: DateTime.utc_now(),
        device_id: "dev_influx_test",
        path: "/interfaces/interface/state/counters",
        source: :gnmi,
        value_float: 42.5,
        value_int: nil,
        value_str: nil
      },
      overrides
    )
  end

  defp make_time_range(start_offset_sec, end_offset_sec \\ 0) do
    now = DateTime.utc_now()

    %{
      start: DateTime.add(now, start_offset_sec, :second),
      end: DateTime.add(now, end_offset_sec, :second)
    }
  end

  # ── insert_batch/1 ──────────────────────────────────────────────────

  describe "insert_batch/1" do
    test "returns {0, nil} for an empty list" do
      assert {0, nil} = InfluxBackend.insert_batch([])
    end

    test "inserts a single metric with value_float" do
      metric = build_metric(%{value_float: 123.456})
      assert {1, nil} = InfluxBackend.insert_batch([metric])
    end

    test "inserts a single metric with value_int" do
      metric = build_metric(%{value_float: nil, value_int: 9999})
      assert {1, nil} = InfluxBackend.insert_batch([metric])
    end

    test "inserts a single metric with value_str" do
      metric = build_metric(%{value_float: nil, value_str: "UP"})
      assert {1, nil} = InfluxBackend.insert_batch([metric])
    end

    test "inserts multiple metrics in a single batch" do
      metrics = [
        build_metric(%{value_float: 10.0, path: "/cpu/util"}),
        build_metric(%{value_float: 20.0, path: "/mem/util"}),
        build_metric(%{value_float: 30.0, path: "/disk/util"})
      ]

      assert {3, nil} = InfluxBackend.insert_batch(metrics)
    end

    test "converts atom source to string tag" do
      metric = build_metric(%{source: :netconf})
      assert {1, nil} = InfluxBackend.insert_batch([metric])

      Process.sleep(500)

      results = InfluxBackend.get_latest("dev_influx_test", minutes: 5, limit: 10)
      assert length(results) >= 1
      assert hd(results).source == "netconf"
    end

    test "defaults to value_float 0.0 when no value fields are set" do
      metric = build_metric(%{value_float: nil, value_int: nil, value_str: nil})
      assert {1, nil} = InfluxBackend.insert_batch([metric])

      Process.sleep(500)

      results = InfluxBackend.get_latest("dev_influx_test", minutes: 5, limit: 10)
      assert length(results) >= 1
      # The fallback 0.0 should be written as value_float
      assert hd(results).value_float == 0.0
    end
  end

  # ── get_latest/2 ────────────────────────────────────────────────────

  describe "get_latest/2" do
    test "returns empty list for unknown device" do
      results = InfluxBackend.get_latest("nonexistent_device_xyz", minutes: 5)
      assert results == []
    end

    test "returns metrics ordered by time descending" do
      now = DateTime.utc_now()
      t1 = DateTime.add(now, -30, :second)
      t2 = DateTime.add(now, -20, :second)
      t3 = DateTime.add(now, -10, :second)

      InfluxBackend.insert_batch([
        build_metric(%{time: t1, value_float: 1.0, device_id: "dev_order_test"}),
        build_metric(%{time: t2, value_float: 2.0, device_id: "dev_order_test"}),
        build_metric(%{time: t3, value_float: 3.0, device_id: "dev_order_test"})
      ])

      Process.sleep(500)

      results = InfluxBackend.get_latest("dev_order_test", minutes: 5, limit: 10)
      assert length(results) == 3

      # Descending time order: most recent first
      values = Enum.map(results, & &1.value_float)
      assert values == [3.0, 2.0, 1.0]
    end

    test "respects the limit option" do
      now = DateTime.utc_now()

      metrics =
        for i <- 1..5 do
          build_metric(%{
            time: DateTime.add(now, -i, :second),
            value_float: i * 1.0,
            device_id: "dev_limit_test"
          })
        end

      InfluxBackend.insert_batch(metrics)
      Process.sleep(500)

      results = InfluxBackend.get_latest("dev_limit_test", minutes: 5, limit: 3)
      assert length(results) == 3
    end

    test "respects the minutes option" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -30, :second)
      old = DateTime.add(now, -600, :second)

      InfluxBackend.insert_batch([
        build_metric(%{time: recent, value_float: 1.0, device_id: "dev_min_test"}),
        build_metric(%{time: old, value_float: 2.0, device_id: "dev_min_test"})
      ])

      Process.sleep(500)

      results = InfluxBackend.get_latest("dev_min_test", minutes: 2, limit: 100)
      # Only the recent one should appear (within last 2 minutes)
      assert length(results) == 1
      assert hd(results).value_float == 1.0
    end

    test "returns normalized metric maps with expected keys" do
      InfluxBackend.insert_batch([
        build_metric(%{value_float: 55.5, device_id: "dev_keys_test"})
      ])

      Process.sleep(500)

      [metric | _] = InfluxBackend.get_latest("dev_keys_test", minutes: 5, limit: 1)
      assert Map.has_key?(metric, :time)
      assert Map.has_key?(metric, :path)
      assert Map.has_key?(metric, :source)
      assert Map.has_key?(metric, :value_float)
      assert Map.has_key?(metric, :value_int)
      assert Map.has_key?(metric, :value_str)
      assert Map.has_key?(metric, :tags)
    end
  end

  # ── query/3 ─────────────────────────────────────────────────────────

  describe "query/3" do
    test "returns empty list for device with no data" do
      time_range = make_time_range(-3600)
      assert InfluxBackend.query("no_data_device", "/some/path", time_range) == []
    end

    test "routes short range (<= 1h) to raw 10s aggregation" do
      now = DateTime.utc_now()
      t1 = DateTime.add(now, -120, :second)

      InfluxBackend.insert_batch([
        build_metric(%{
          time: t1,
          value_float: 42.0,
          device_id: "dev_short_q",
          path: "/cpu/util"
        })
      ])

      Process.sleep(500)

      time_range = %{start: DateTime.add(now, -1800, :second), end: now}
      result = InfluxBackend.query("dev_short_q", "/cpu/util", time_range)
      assert is_list(result)
      assert length(result) >= 1
      assert Map.has_key?(hd(result), :bucket)
      assert Map.has_key?(hd(result), :avg_value)
    end

    test "routes medium range (1h-24h) to 5m downsampled data or fallback" do
      now = DateTime.utc_now()
      # 2 hours ago
      time_range = %{start: DateTime.add(now, -7200, :second), end: now}
      result = InfluxBackend.query("dev_medium_q", "/cpu/util", time_range)
      assert is_list(result)
    end

    test "routes long range (>24h) to 1h downsampled data or fallback" do
      now = DateTime.utc_now()
      # 48 hours ago
      time_range = %{start: DateTime.add(now, -172_800, :second), end: now}
      result = InfluxBackend.query("dev_long_q", "/cpu/util", time_range)
      assert is_list(result)
    end
  end

  # ── query_raw/4 ─────────────────────────────────────────────────────

  describe "query_raw/4" do
    test "returns empty list when no data matches" do
      time_range = make_time_range(-3600)
      result = InfluxBackend.query_raw("no_data_dev", "/no/path", "1 minute", time_range)
      assert result == []
    end

    test "returns aggregated results with bucket, avg, max, min, count" do
      now = DateTime.utc_now()
      # Align to start of a minute so all points land in the same bucket
      minute_start =
        now
        |> DateTime.add(-120, :second)
        |> Map.put(:second, 0)
        |> Map.put(:microsecond, {0, 6})

      t1 = DateTime.add(minute_start, 5, :second)
      t2 = DateTime.add(minute_start, 15, :second)
      t3 = DateTime.add(minute_start, 25, :second)

      InfluxBackend.insert_batch([
        build_metric(%{time: t1, value_float: 10.0, device_id: "dev_raw_agg", path: "/cpu"}),
        build_metric(%{time: t2, value_float: 30.0, device_id: "dev_raw_agg", path: "/cpu"}),
        build_metric(%{time: t3, value_float: 20.0, device_id: "dev_raw_agg", path: "/cpu"})
      ])

      Process.sleep(500)

      time_range = %{
        start: minute_start,
        end: DateTime.add(minute_start, 60, :second)
      }

      result = InfluxBackend.query_raw("dev_raw_agg", "/cpu", "1 minute", time_range)
      assert length(result) >= 1

      agg = hd(result)
      assert Map.has_key?(agg, :bucket)
      assert Map.has_key?(agg, :avg_value)
      assert Map.has_key?(agg, :max_value)
      assert Map.has_key?(agg, :min_value)
      assert Map.has_key?(agg, :sample_count)

      assert agg.avg_value == 20.0
      assert agg.max_value == 30.0
      assert agg.min_value == 10.0
      assert agg.sample_count == 3
    end

    test "accepts all valid bucket sizes" do
      time_range = make_time_range(-3600)

      for bucket_size <- [
            "10 seconds",
            "30 seconds",
            "1 minute",
            "5 minutes",
            "15 minutes",
            "1 hour"
          ] do
        result = InfluxBackend.query_raw("dev_test", "/test", bucket_size, time_range)
        assert is_list(result), "expected list for bucket_size #{bucket_size}"
      end
    end

    test "raises FunctionClauseError for invalid bucket size" do
      time_range = make_time_range(-3600)

      assert_raise FunctionClauseError, fn ->
        InfluxBackend.query_raw("dev_test", "/test", "2 minutes", time_range)
      end
    end
  end

  # ── query_rate/4 ────────────────────────────────────────────────────

  describe "query_rate/4" do
    test "returns empty list when no data matches" do
      time_range = make_time_range(-3600)
      result = InfluxBackend.query_rate("no_data_dev", "/no/path", "1 minute", time_range)
      assert result == []
    end

    test "computes rate from counter values (value_int)" do
      now = DateTime.utc_now()
      # Align to start of a minute
      minute_start =
        now
        |> DateTime.add(-120, :second)
        |> Map.put(:second, 0)
        |> Map.put(:microsecond, {0, 6})

      t1 = DateTime.add(minute_start, 10, :second)
      t2 = DateTime.add(minute_start, 20, :second)
      t3 = DateTime.add(minute_start, 30, :second)

      InfluxBackend.insert_batch([
        build_metric(%{
          time: t1,
          device_id: "dev_rate_test",
          path: "/if/counters/in-octets",
          value_float: nil,
          value_int: 1000
        }),
        build_metric(%{
          time: t2,
          device_id: "dev_rate_test",
          path: "/if/counters/in-octets",
          value_float: nil,
          value_int: 2000
        }),
        build_metric(%{
          time: t3,
          device_id: "dev_rate_test",
          path: "/if/counters/in-octets",
          value_float: nil,
          value_int: 3500
        })
      ])

      Process.sleep(500)

      time_range = %{
        start: minute_start,
        end: DateTime.add(minute_start, 60, :second)
      }

      result =
        InfluxBackend.query_rate(
          "dev_rate_test",
          "/if/counters/in-octets",
          "1 minute",
          time_range
        )

      assert length(result) == 1

      rate_row = hd(result)
      assert Map.has_key?(rate_row, :bucket)
      assert Map.has_key?(rate_row, :rate_per_sec)
      assert %Decimal{} = rate_row.rate_per_sec
      # rate = (max - min) / interval = (3500 - 1000) / 60 = 41.67
      assert Decimal.gt?(rate_row.rate_per_sec, Decimal.new(0))
    end

    test "raises FunctionClauseError for invalid bucket size" do
      time_range = make_time_range(-3600)

      assert_raise FunctionClauseError, fn ->
        InfluxBackend.query_rate("dev_test", "/test", "3 minutes", time_range)
      end
    end
  end
end
