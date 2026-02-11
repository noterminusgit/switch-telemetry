# Phase 9 Implementation Plan: Testing & CI/CD

## Wave 1: Context & Query Tests (parallel agents)

### Agent A: Metrics Context + Queries Tests
1. Create `test/switch_telemetry/metrics_test.exs`:
   - `insert_batch/1`: insert multiple metrics, verify records in DB
   - `insert_batch/1`: handles empty list
   - `get_latest/2`: returns latest metrics ordered by time desc
   - `get_latest/2`: respects limit and minutes options
   - `get_time_series/4`: returns time-bucketed aggregations
   - `get_time_series/4`: rejects invalid bucket sizes
2. Expand `test/switch_telemetry/metrics/query_router_test.exs`:
   - `query_rate/4`: with actual data, verify rate calculation
   - `query_aggregate/4`: test with inserted data
   - verify time_range routing thresholds with actual data
3. Tests: ~12-15 new tests

### Agent B: Devices + Dashboards Context Tests
1. Create `test/switch_telemetry/devices_test.exs`:
   - `list_devices/0`: returns all devices
   - `list_devices_by_status/1`: filters by status
   - `get_device!/1`: returns device, raises on missing
   - `create_device/1`: creates with valid attrs, rejects invalid
   - `update_device/2`: updates fields
   - `delete_device/1`: removes device
   - Credential CRUD: create, update, delete
2. Create `test/switch_telemetry/dashboards_test.exs`:
   - `list_dashboards/0`: returns all dashboards
   - `get_dashboard!/1`: returns with preloaded widgets
   - `create_dashboard/1`: valid and invalid
   - `update_dashboard/2`: updates fields
   - `delete_dashboard/1`: cascades to widgets
   - `add_widget/2`: adds widget to dashboard
   - `update_widget/2`, `delete_widget/1`
3. Tests: ~18-22 new tests

## Wave 2: Collector + Component Tests + CI (parallel agents)

### Agent C: Collector Protocol Tests
1. Expand `test/switch_telemetry/collector/gnmi_session_test.exs`:
   - Test `parse_notification/2` via extracted logic: timestamp conversion, path formatting, value extraction
   - Test `parse_path_string/1` path parsing with keys
   - Test `format_path/2` with prefix + path + keys
   - Test `schedule_retry/1` exponential backoff calculation
   - Test struct initialization and default state
2. Expand `test/switch_telemetry/collector/netconf_session_test.exs`:
   - Test `extract_messages/1`: single message, multiple messages, partial buffer
   - Test `parse_netconf_response/2` via extracted logic: XML parsing with SweetXml
   - Test `build_get_rpc/2`: correct XML structure
   - Test value parsing: parse_float, parse_int, numeric?
3. Expand `test/switch_telemetry/collector/device_manager_test.exs`:
   - Test init state
   - Test struct and session tracking
4. Tests: ~15-20 new tests

### Agent D: GitHub Actions CI + Dockerfile
1. Create `.github/workflows/ci.yml`:
   - Trigger on push to master + PRs
   - Service: timescale/timescaledb:latest-pg16
   - Setup: erlef/setup-beam with Elixir 1.17.3, OTP 27
   - Cache: deps + _build
   - Steps: deps.get, compile --warnings-as-errors, format --check-formatted, test
2. Create `Dockerfile` (multi-stage):
   - Builder stage: elixir base, deps, compile, release
   - Runner stage: debian-slim, minimal runtime
   - Support both `web` and `collector` releases via build arg
3. Create `docker-compose.yml`:
   - db: timescale/timescaledb:latest-pg16
   - web: switch-telemetry web release
   - collector: switch-telemetry collector release
4. Create `.dockerignore`
