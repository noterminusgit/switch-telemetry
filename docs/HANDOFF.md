# Handoff Documentation

## Project Status

**Location**: `/home/dude/switch-telemetry/`
**State**: Phases 1-4 complete. 74 tests passing, zero warnings.
**Ready for**: Phase 5 implementation (Alerting & Notifications).

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
| `docs/design/phase-1-foundation.md` | Phase 1 design (Foundation) |
| `docs/plans/phase-1-foundation.md` | Phase 1 implementation plan |
| `docs/design/phase-5-alerting.md` | Phase 5 design (Alerting & Notifications) |
| `docs/plans/phase-5-alerting.md` | Phase 5 implementation plan |
| `docs/design/phase-6-auth.md` | Phase 6 design (Authentication & Authorization) |
| `docs/design/phase-7-security-audit.md` | Phase 7 design (Security Audit) |

## Implementation Phases

### Phase 1: Foundation (Week 1-2) -- COMPLETE
- `mix phx.new switch_telemetry --no-mailer --no-dashboard`
- Add dependencies (timescale, grpc, protobuf, sweet_xml, vega_lite, tucan, horde, libcluster, oban)
- Install npm packages in assets/ (vega, vega-lite, vega-embed)
- Create Ecto schemas and migrations (devices, metrics hypertable, credentials, dashboards, widgets)
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
- Continuous aggregate migrations

### Phase 4: Distribution & Scale (Week 7-8) -- COMPLETE
- libcluster configuration for BEAM clustering
- Horde setup for distributed device sessions
- Consistent hashing device assignment
- NodeMonitor for failover handling
- Docker/Kubernetes deployment manifests
- Load testing with simulated devices

### Phase 5: Alerting & Notifications (Week 9-10)
- Alert rules: threshold-based conditions on metric paths (above, below, absent, rate_increase)
- Alert events: immutable log of every state change (firing, resolved, acknowledged)
- Notification channels: webhook, Slack, email (Swoosh)
- AlertEvaluator Oban worker: periodic rule evaluation against recent metrics
- AlertNotifier Oban worker: async dispatch per (event, channel) pair
- AlertLive: manage rules, view active alerts, event history, channel configuration
- Real-time alert badges on dashboard header and device pages via PubSub
- New deps: Finch (HTTP client), Swoosh (email)
- Design: `docs/design/phase-5-alerting.md`
- Plan: `docs/plans/phase-5-alerting.md`

### Phase 6: Authentication & Authorization (Week 11-12)
- User accounts with session-based auth (phx.gen.auth pattern)
- Three roles: admin, operator, viewer with permission matrix
- Dashboard ownership (created_by field)
- Role-gated routes: viewers read-only, operators manage devices/alerts/own dashboards, admins manage all
- User management UI (admin only)
- User settings (change email/password)
- Login rate limiting
- New deps: bcrypt_elixir
- Design: `docs/design/phase-6-auth.md`

### Phase 7: Security Audit (Week 13-14)
- Credential encryption: wire up Cloak Vault, encrypt device credentials at rest
- Input validation: review all changesets, raw SQL, atom creation, string lengths
- Transport security: force_ssl, HSTS, secure cookies, TLS verification
- Content Security Policy: CSP headers (document Vega unsafe-eval requirement)
- Secrets management: audit env vars, signing salts, .gitignore patterns
- Dependency audit: mix hex.audit, npm audit, update vulnerable deps
- Logging security: redact credentials/tokens from logs, filter sensitive params
- BEAM security: distribution cookie, firewall docs, catch-all handle_info clauses
- Deliverables: audit checklist, production hardening guide, env var documentation
- Design: `docs/design/phase-7-security-audit.md`

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

Implementor should begin Phase 5 (Alerting & Notifications):
1. Read design: `docs/design/phase-5-alerting.md`
2. Read plan: `docs/plans/phase-5-alerting.md`
3. Execute tasks in group order (Groups 1-6, 15 tasks total)
4. TDD: write tests first, then implementation
