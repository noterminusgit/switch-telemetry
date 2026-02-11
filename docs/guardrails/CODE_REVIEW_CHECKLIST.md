# Code Review Checklist

## Correctness
- [ ] gNMI path parsing handles vendor-specific YANG origins
- [ ] NETCONF XML responses are parsed with SweetXml, not regex
- [ ] TypedValue extraction handles all gNMI value types (float, int, uint, string, json, bytes)
- [ ] SSH/gRPC connection failures are caught and trigger reconnection
- [ ] PubSub broadcasts happen AFTER successful database writes

## Data Integrity
- [ ] Metrics are batch-inserted, not individually
- [ ] All metric queries include a time range predicate
- [ ] Hypertable indexes include the time column
- [ ] Continuous aggregates used for queries spanning > 1 hour
- [ ] No unbounded queries against the metrics hypertable

## Security
- [ ] No credentials in source code or logs
- [ ] Device credentials encrypted at rest (Cloak.Ecto)
- [ ] Full NETCONF XML responses not logged (may contain configs/secrets)
- [ ] SSH host key verification configured appropriately
- [ ] gRPC TLS configured for production

## Architecture
- [ ] Collector-only code doesn't run on web nodes (check NODE_ROLE guards)
- [ ] Oban workers only scheduled on collector nodes
- [ ] Device sessions registered with Horde (cluster-wide uniqueness)
- [ ] PubSub subscriptions guarded by `connected?/1` in LiveView

## Performance
- [ ] LiveView chart data trimmed to max point count (< 500 points)
- [ ] QueryRouter selects appropriate data source for time range
- [ ] Exponential backoff on device reconnection (no thundering herd)
- [ ] Batch sizes appropriate for TimescaleDB (100-1000 rows per insert)

## Testing
- [ ] Device connections mocked with Mox
- [ ] Protocol parsing tested with real vendor fixture files
- [ ] Ecto sandbox used for database tests
- [ ] PubSub integration tested (broadcast → LiveView handle_info)
