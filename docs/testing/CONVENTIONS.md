# Testing Conventions

Quick reference for writing tests in Switch Telemetry.

## File Layout

Test files mirror `lib/` structure with `_test.exs` suffix:

```
lib/switch_telemetry/devices.ex        -> test/switch_telemetry/devices_test.exs
lib/switch_telemetry/devices/device.ex -> test/switch_telemetry/devices/device_test.exs
lib/switch_telemetry_web/live/...      -> test/switch_telemetry_web/live/..._test.exs
```

Property-based tests use `_property_test.exs` suffix:

```
test/switch_telemetry/alerting/evaluator_property_test.exs
test/switch_telemetry/authorization_property_test.exs
test/switch_telemetry/collector/subscription_property_test.exs
```

## Case Templates

### `SwitchTelemetry.DataCase`

For schemas, contexts, workers, and anything touching PostgreSQL.

```elixir
defmodule SwitchTelemetry.Devices.DeviceTest do
  use SwitchTelemetry.DataCase, async: true
  # ...
end
```

Provides: `Repo`, `Ecto`, `Ecto.Changeset`, `Ecto.Query`, `errors_on/1`. Sets up SQL sandbox automatically.

### `SwitchTelemetryWeb.ConnCase`

For controllers, LiveViews, plugs, and anything needing an HTTP connection.

```elixir
defmodule SwitchTelemetryWeb.DeviceLiveTest do
  use SwitchTelemetryWeb.ConnCase, async: true
  # ...
end
```

Provides: `Plug.Conn`, `Phoenix.ConnTest`, verified routes, `@endpoint`. Sets up SQL sandbox and provides `conn` in context.

Auth helpers:
- `register_and_log_in_user/1` -- accepts `%{conn: conn}`, optional `:role` and `:user_attrs`
- `create_test_user/1` -- creates user with optional `%{role: :admin}` or `%{user_attrs: %{...}}`
- `log_in_user/2` -- puts session token into conn

### `SwitchTelemetry.InfluxCase`

For tests that read/write InfluxDB. Always `async: false`.

```elixir
defmodule SwitchTelemetry.Metrics.InfluxBackendTest do
  use SwitchTelemetry.InfluxCase, async: false
  # ...
end
```

Provides: `InfluxDB`, `Metrics` aliases. Clears the `metrics_test` bucket before each test.

## Async Rules

| Case Template | Default async | Notes |
|---------------|---------------|-------|
| `DataCase` | `async: true` | Safe with SQL sandbox |
| `ConnCase` | `async: true` | Safe with SQL sandbox |
| `InfluxCase` | `async: false` | **Required** -- InfluxDB has no sandbox, tests share a bucket |
| `ExUnit.Case` | `async: true` | Pure logic (property tests, evaluator, etc.) |

Exceptions requiring `async: false` even with DataCase/ConnCase:
- Tests using shared global state (ETS tables, named GenServers)
- Integration tests (`alerting/integration_test.exs`)
- StreamMonitor LiveView test (shared GenServer state)

## InfluxDB Test Patterns

```elixir
use SwitchTelemetry.InfluxCase, async: false

# Build metric helper (define locally or inline)
defp build_metric(overrides) do
  Map.merge(
    %{
      time: DateTime.utc_now(),
      device_id: "dev_test",
      path: "/interfaces/interface/state/counters",
      source: :gnmi,
      value_float: 42.5,
      value_int: nil,
      value_str: nil
    },
    overrides
  )
end

test "insert and query" do
  metric = build_metric(%{value_float: 99.9})
  assert {1, nil} = InfluxBackend.insert_batch([metric])

  # Wait for InfluxDB write consistency
  Process.sleep(500)

  result = InfluxBackend.get_latest("dev_test", limit: 1)
  assert length(result) == 1
end
```

Key rules:
- Always use `metrics_test` bucket (configured in `config/test.exs`)
- `Process.sleep(500)` after writes before reads for consistency
- InfluxCase clears the bucket before each test (with 50ms delay)
- Timestamps are nanoseconds for writes, nanosecond integers in query results

## Mox

Defined in `test/support/mocks.ex`:

```elixir
Mox.defmock(SwitchTelemetry.Metrics.MockBackend, for: SwitchTelemetry.Metrics.Backend)
```

Usage in tests:

```elixir
setup do
  Mox.stub(SwitchTelemetry.Metrics.MockBackend, :get_latest, fn _id, _opts -> [] end)
  :ok
end
```

The mock is configured via `Application.put_env(:switch_telemetry, :metrics_backend, MockBackend)` when needed in test setup.

## Property Tests

Use `ExUnitProperties` with `StreamData` generators. File suffix: `_property_test.exs`.

```elixir
defmodule SwitchTelemetry.Alerting.EvaluatorPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "fires iff value > threshold" do
    check all(
            value <- float(min: -1_000_000.0, max: 1_000_000.0),
            threshold <- float(min: -1_000_000.0, max: 1_000_000.0)
          ) do
      result = Evaluator.check_condition(:above, value, threshold)
      if value > threshold, do: assert({:firing, ^value} = result), else: assert(:ok = result)
    end
  end
end
```

These tests do not require DataCase unless they touch the database.

## Changeset Testing

Use `errors_on/1` from DataCase:

```elixir
test "validates required fields" do
  changeset = Device.changeset(%Device{}, %{})
  assert %{hostname: ["can't be blank"]} = errors_on(changeset)
end
```

## Test Helper

`test/test_helper.exs` boots ExUnit and sets SQL sandbox to manual mode. The case templates handle sandbox ownership per test.

## Running Tests

```bash
mix test                           # all tests
mix test test/switch_telemetry/    # directory
mix test test/path/to_test.exs     # single file
mix test test/path/to_test.exs:42  # single test by line
mix test --only property           # tagged tests (if tagged)
```
