# Handoff Documentation

## Project Status

**Location**: `/home/dude/switch-telemetry/`
**State**: Architecture documentation complete. No code implementation yet.
**Ready for**: Phase 1 implementation (project scaffolding + core schemas).

## Documentation Index

| File | Contents |
|---|---|
| `README.md` | Project overview, tech stack, getting started |
| `CLAUDE.md` | AI agent context, code conventions, common mistakes |
| `docs/architecture/00_SYSTEM_OVERVIEW.md` | Vision, component diagram, data flow, TSDB real-time answer |
| `docs/architecture/01_DOMAIN_MODEL.md` | Entities (Device, Metric, Subscription, Dashboard, Widget, Credential) |
| `docs/architecture/02_DATA_LAYER.md` | TimescaleDB migrations, schemas, query patterns, indexing |
| `docs/architecture/03_COLLECTOR_PROTOCOLS.md` | gNMI and NETCONF client implementations |
| `docs/architecture/04_DISTRIBUTED_ARCHITECTURE.md` | Node separation, Mix releases, clustering, device assignment |
| `docs/architecture/05_DASHBOARD_UI.md` | VegaLite/Tucan charts, LiveView dashboards, query routing |
| `docs/architecture/06_LIFECYCLE.md` | Supervision tree, GenServer rules, failover, telemetry |
| `docs/decisions/ADR-001-timeseries-database.md` | TimescaleDB vs InfluxDB vs ClickHouse |
| `docs/decisions/ADR-002-node-separation.md` | Collector vs Web node types |
| `docs/decisions/ADR-003-charting-library.md` | VegaLite/Tucan vs Plox vs Contex |
| `docs/decisions/ADR-004-protocol-clients.md` | Custom gNMI/NETCONF clients |
| `docs/guardrails/NEVER_DO.md` | 10 critical prohibitions with code examples |
| `docs/guardrails/ALWAYS_DO.md` | 20 mandatory practices |
| `docs/guardrails/CODE_REVIEW_CHECKLIST.md` | Review checklist for PRs |

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
- `mix phx.new switch_telemetry --no-mailer --no-dashboard`
- Add dependencies (timescale, grpc, protobuf, sweet_xml, vega_lite, tucan, horde, libcluster, oban)
- Install npm packages in assets/ (vega, vega-lite, vega-embed)
- Create Ecto schemas and migrations (devices, metrics hypertable, credentials, dashboards, widgets)
- Configure dual Mix releases (collector + web)
- Set up conditional supervision tree with NODE_ROLE

### Phase 2: Collector Core (Week 3-4)
- Compile gNMI proto files, generate Elixir stubs
- Implement GnmiSession GenServer (connect, subscribe, parse notifications)
- Implement NetconfSession GenServer (SSH connect, XML RPC, parse responses)
- Implement DeviceManager (start/stop sessions, assignment)
- Implement batch metric insertion
- PubSub broadcasting from collectors

### Phase 3: Dashboard UI (Week 5-6)
- Dashboard CRUD (create, edit, delete dashboards)
- Widget configuration UI (add/remove widgets, choose metrics, set time ranges)
- TelemetryChart LiveComponent wrapping VegaLite/Tucan with VegaLiteHook
- LiveView with PubSub subscriptions for real-time updates
- QueryRouter for intelligent data source selection
- Continuous aggregate migrations

### Phase 4: Distribution & Scale (Week 7-8)
- libcluster configuration for BEAM clustering
- Horde setup for distributed device sessions
- Consistent hashing device assignment
- NodeMonitor for failover handling
- Docker/Kubernetes deployment manifests
- Load testing with simulated devices

## Key Hex Dependencies

```elixir
defp deps do
  [
    # Web
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 1.0"},
    {:vega_lite, "~> 0.1"},
    {:tucan, "~> 0.5"},

    # Database
    {:ecto_sql, "~> 3.12"},
    {:postgrex, ">= 0.0.0"},
    {:timescale, "~> 0.1"},

    # Protocols
    {:grpc, "~> 0.11"},
    {:protobuf, "~> 0.14"},
    {:sweet_xml, "~> 0.7"},

    # Distribution
    {:libcluster, "~> 3.4"},
    {:horde, "~> 0.9"},

    # Background jobs
    {:oban, "~> 2.17"},

    # Security
    {:cloak_ecto, "~> 1.3"},

    # Utilities
    {:jason, "~> 1.4"},
    {:hash_ring, "~> 0.4"}
  ]
end
```

## Next Steps

Director AI should begin with Phase 1:
1. Create a design document in `docs/design/phase-1-foundation.md`
2. Create an implementation plan in `docs/plans/phase-1-foundation.md`
3. Hand off to Implementor for execution
