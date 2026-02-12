# Handoff Documentation

## Project Status

**Location**: `/home/dude/switch-telemetry/`
**State**: Phases 1-9 complete. 527 tests passing, zero warnings, CI green.
**Ready for**: Next feature development.

## Documentation Index

| File | Contents |
|---|---|
| `README.md` | Project overview, tech stack, getting started |
| `CLAUDE.md` | AI agent context, code conventions, common mistakes |
| `docs/architecture/00_SYSTEM_OVERVIEW.md` | Vision, component diagram, data flow, TSDB real-time answer |
| `docs/architecture/01_DOMAIN_MODEL.md` | Entities (Device, Metric, Subscription, Dashboard, Widget, Credential) |
| `docs/architecture/02_DATA_LAYER.md` | InfluxDB v2 buckets, Flux queries, Instream client, backend abstraction |
| `docs/architecture/03_COLLECTOR_PROTOCOLS.md` | gNMI and NETCONF client implementations |
| `docs/architecture/04_DISTRIBUTED_ARCHITECTURE.md` | Node separation, Mix releases, clustering, device assignment |
| `docs/architecture/05_DASHBOARD_UI.md` | VegaLite/Tucan charts, LiveView dashboards, query routing |
| `docs/architecture/06_LIFECYCLE.md` | Supervision tree, GenServer rules, failover, telemetry |
| `docs/decisions/ADR-001-timeseries-database.md` | InfluxDB v2 (superseded original TimescaleDB decision) |
| `docs/decisions/ADR-005-influxdb-migration.md` | Migration from TimescaleDB to InfluxDB v2 |
| `docs/decisions/ADR-002-node-separation.md` | Collector vs Web node types |
| `docs/decisions/ADR-003-charting-library.md` | VegaLite/Tucan vs Plox vs Contex |
| `docs/decisions/ADR-004-protocol-clients.md` | Custom gNMI/NETCONF clients |
| `docs/guardrails/NEVER_DO.md` | 10 critical prohibitions with code examples |
| `docs/guardrails/ALWAYS_DO.md` | 20 mandatory practices |
| `docs/guardrails/CODE_REVIEW_CHECKLIST.md` | Review checklist for PRs |
| `docs/design/phase-1-foundation.md` | Phase 1 design (Foundation) |
| `docs/plans/phase-1-foundation.md` | Phase 1 implementation plan |
| `docs/design/phase-5-alerting.md` | Phase 5 design (Alerting & Notifications) |
| `docs/plans/phase-5-alerting.md` | Phase 5 implementation plan |
| `docs/design/phase-6-auth.md` | Phase 6 design (Authentication & Authorization) |
| `docs/design/phase-7-security-audit.md` | Phase 7 design (Security Audit) |

## Implementation Phases

### Phase 1: Foundation (Week 1-2) -- COMPLETE
- `mix phx.new switch_telemetry --no-mailer --no-dashboard`
- Add dependencies (instream, grpc, protobuf, sweet_xml, vega_lite, tucan, horde, libcluster, oban)
- Install npm packages in assets/ (vega, vega-lite, vega-embed)
- Create Ecto schemas and migrations (devices, credentials, dashboards, widgets) + InfluxDB bucket setup
- Configure dual Mix releases (collector + web)
- Set up conditional supervision tree with NODE_ROLE

### Phase 2: Collector Core (Week 3-4) -- COMPLETE
- Compile gNMI proto files, generate Elixir stubs
- Implement GnmiSession GenServer (connect, subscribe, parse notifications)
- Implement NetconfSession GenServer (SSH connect, XML RPC, parse responses)
- Implement DeviceManager (start/stop sessions, assignment)
- Implement batch metric insertion
- PubSub broadcasting from collectors

### Phase 3: Dashboard UI (Week 5-6) -- COMPLETE
- Dashboard CRUD (create, edit, delete dashboards)
- Widget configuration UI (add/remove widgets, choose metrics, set time ranges)
- TelemetryChart LiveComponent wrapping VegaLite/Tucan with VegaLiteHook
- LiveView with PubSub subscriptions for real-time updates
- QueryRouter for intelligent data source selection
- InfluxDB Flux task configuration (5m and 1h downsampling)

### Phase 4: Distribution & Scale (Week 7-8) -- COMPLETE
- libcluster configuration for BEAM clustering
- Horde setup for distributed device sessions
- Consistent hashing device assignment
- NodeMonitor for failover handling
- Docker/Kubernetes deployment manifests
- Load testing with simulated devices

### Phase 5: Alerting & Notifications (Week 9-10) -- COMPLETE
- Alert rules, events, notification channels, channel bindings
- AlertEvaluator, AlertNotifier, AlertEventPruner Oban workers
- AlertLive with real-time PubSub updates
- New deps: Finch, Swoosh

### Phase 6: Authentication & Authorization (Week 11-12) -- COMPLETE
- User/UserToken schemas, session-based auth, remember-me cookie
- Role-based authorization (admin/operator/viewer)
- Dashboard/AlertRule ownership via created_by FK
- Login UI, UserLive.Settings, admin UserLive.Index

### Phase 7: Security Audit (Week 13-14) -- COMPLETE
- Cloak Vault for credential encryption at rest (AES-256-GCM)
- Input validation, CSP headers, force_ssl, HSTS
- filter_parameters for log redaction
- docs/security/: ENV_VARS.md, PRODUCTION_HARDENING.md, AUDIT_CHECKLIST.md

### Phase 8-9: InfluxDB Migration -- COMPLETE
- Migrated time-series metrics from TimescaleDB to InfluxDB v2
- Created Backend behaviour + InfluxBackend implementation
- Instream client with Flux queries (raw, aggregated, rate)
- InfluxDB bucket setup scripts + Flux downsampling tasks
- Removed TimescaleDB extension dependency
- PostgreSQL retained for all relational data

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
    {:instream, "~> 2.2"},

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

All core phases (1-9) are complete. 527 tests passing, zero warnings, CI green.

Potential next areas:
1. SNMP collector support
2. API key authentication for programmatic access
3. Dashboard sharing and export
4. Grafana-style template variables
5. Performance optimization and load testing
