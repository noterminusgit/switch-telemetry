defmodule SwitchTelemetry.Metrics.QueryRouterTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Metrics.QueryRouter

  describe "query/3" do
    test "returns empty list for device with no data" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -3600, :second), end: now}

      result = QueryRouter.query("nonexistent_device", "/some/path", time_range)
      assert result == []
    end

    test "routes short ranges (< 1h) to raw table" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -1800, :second), end: now}

      result = QueryRouter.query("dev_test", "/test/path", time_range)
      assert is_list(result)
    end

    test "routes medium ranges (1h-24h) to 5m aggregate" do
      now = DateTime.utc_now()
      time_range = %{start: DateTime.add(now, -7200, :second), end: now}

      result = QueryRouter.query("dev_test", "/test/path", time_range)
      assert is_list(result)
    end

    test "routes long ranges (>24h) to 1h aggregate" do
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

      SwitchTelemetry.Repo.insert_all("metrics", [
        %{
          time: now,
          device_id: "dev_qr_test",
          path: "/test/counters",
          source: "gnmi",
          tags: %{},
          value_float: 42.5,
          value_int: nil,
          value_str: nil
        }
      ])

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
  end
end
