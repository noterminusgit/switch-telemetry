# Phase 9 Design: Testing & CI/CD

## Overview

Strengthen test coverage for undertested modules and add GitHub Actions CI/CD pipeline. Current state: 359 tests, 0 failures. Coverage is excellent for accounts/alerting/security but critically weak for collector protocols, metrics queries, and context modules. No CI exists.

## Coverage Gaps to Fix

### High Priority - Context Module Tests
- `SwitchTelemetry.Metrics` context: `insert_batch/2`, `get_latest/2` untested
- `SwitchTelemetry.Metrics.Queries`: `time_bucket` queries, aggregations untested
- `SwitchTelemetry.Devices` context: CRUD operations untested
- `SwitchTelemetry.Dashboards` context: only advanced_test exists, basic CRUD needs coverage

### Medium Priority - Collector Protocol Tests
- `GnmiSession`: only 6 basic tests, missing stream handling, reconnection, update parsing
- `NetconfSession`: only 2 tests, missing SSH session, XML parsing, poll cycle
- `DeviceManager`: only `function_exported?` checks, needs session lifecycle tests
- `NodeMonitor`: only `function_exported?` checks, needs cluster event tests

### Lower Priority - Component Tests
- `TelemetryChart`: VegaLite spec generation untested directly
- `WidgetEditor`: form handling, query builder untested
- `TimeRangePicker`: preset selection, custom range untested

## CI/CD Pipeline

### GitHub Actions Workflow
- **Trigger**: push to master, pull requests
- **Matrix**: Elixir 1.17.3 / OTP 27
- **Steps**:
  1. Checkout code
  2. Install Erlang/Elixir via erlef/setup-beam action
  3. Cache deps + _build
  4. `mix deps.get`
  5. `mix compile --warnings-as-errors`
  6. `mix format --check-formatted`
  7. `mix test`
- **Services**: PostgreSQL 16 with TimescaleDB extension
- **Secrets**: CLOAK_KEY (test key is fine in CI)

### Dockerfile
- Multi-stage build: builder (compile) + runner (minimal runtime)
- Based on elixir:1.17.3-otp-27
- Production release with `mix release web` and `mix release collector`

### docker-compose.yml
- `db`: timescale/timescaledb:latest-pg16
- `web`: switch-telemetry web release
- `collector`: switch-telemetry collector release

## Testing Strategy

### Context Tests Pattern
```elixir
defmodule SwitchTelemetry.MetricsTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Metrics

  describe "insert_batch/2" do
    test "inserts multiple metrics" do
      # Create device, insert batch, verify records
    end
  end

  describe "get_latest/2" do
    test "returns latest metrics for device" do
      # Insert metrics, query, verify ordering
    end
  end
end
```

### Collector Tests Pattern
Use Mox for external dependencies (:ssh, gRPC), test GenServer callbacks directly:
```elixir
# Test init, handle_info, handle_cast with mocked connections
```

### Component Tests Pattern
Test LiveComponent update/render directly:
```elixir
defmodule SwitchTelemetryWeb.Components.TelemetryChartTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "builds correct VegaLite spec for line chart" do
    # Test spec building logic
  end
end
```
