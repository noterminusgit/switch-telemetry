# 00: System Overview

## Vision

Switch Telemetry provides a single platform for collecting, storing, and visualizing network device telemetry from thousands of devices using modern streaming protocols (gNMI, NETCONF). It replaces fragmented SNMP polling with a scalable, real-time architecture built on the BEAM VM.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BEAM Cluster (libcluster)                    │
│                                                                     │
│  ┌──────────────────────┐     Phoenix.PubSub (:pg)                 │
│  │   Collector Nodes    │─────────────────────────┐                │
│  │                      │                         │                │
│  │  ┌───────────────┐   │                         ▼                │
│  │  │ gNMI Sessions │   │              ┌────────────────────┐      │
│  │  │ (GenServer per │   │              │    Web Nodes       │      │
│  │  │  device, gRPC  │   │              │                    │      │
│  │  │  Subscribe     │   │              │  ┌──────────────┐  │      │
│  │  │  streams)      │   │              │  │ Phoenix      │  │      │
│  │  └───────────────┘   │              │  │ LiveView     │  │      │
│  │                      │              │  │              │  │      │
│  │  ┌───────────────┐   │              │  │ ┌──────────┐ │  │      │
│  │  │ NETCONF       │   │              │  │ │ VegaLite │ │  │      │
│  │  │ Sessions      │   │              │  │ │ /Tucan   │ │  │      │
│  │  │ (GenServer per │   │              │  │ │ Charts   │ │  │      │
│  │  │  device, SSH)  │   │              │  │ └──────────┘ │  │      │
│  │  └───────────────┘   │              │  └──────────────┘  │      │
│  │                      │              │                    │      │
│  │  ┌───────────────┐   │              │  ┌──────────────┐  │      │
│  │  │ Horde         │◄──┼──────────────┼──┤ Dashboard    │  │      │
│  │  │ Distributed   │   │              │  │ Config       │  │      │
│  │  │ Supervisor    │   │              │  │ (user-defined│  │      │
│  │  └───────────────┘   │              │  │  widgets)    │  │      │
│  │                      │              │  └──────────────┘  │      │
│  │  ┌───────────────┐   │              └────────────────────┘      │
│  │  │ Oban Workers  │   │                                          │
│  │  │ (discovery,   │   │                                          │
│  │  │  maintenance) │   │                                          │
│  │  └───────────────┘   │                                          │
│  └──────────┬───────────┘                                          │
│             │                                                       │
└─────────────┼───────────────────────────────────────────────────────┘
              │
              ▼
    ┌──────────────────┐
    │   TimescaleDB    │
    │  (PostgreSQL +   │
    │   hypertables)   │
    │                  │
    │  ┌────────────┐  │
    │  │ metrics    │  │  ← hypertable, partitioned by time
    │  │ (raw)      │  │
    │  ├────────────┤  │
    │  │ metrics_5m │  │  ← continuous aggregate (5-minute buckets)
    │  ├────────────┤  │
    │  │ metrics_1h │  │  ← continuous aggregate (1-hour buckets)
    │  ├────────────┤  │
    │  │ devices    │  │  ← device inventory (standard table)
    │  ├────────────┤  │
    │  │ dashboards │  │  ← user dashboard configurations
    │  └────────────┘  │
    └──────────────────┘
```

## Component Overview

### Collector Nodes (headless)

**Purpose**: Maintain persistent connections to network devices and ingest telemetry.

- **GnmiSession** -- GenServer per device. Opens a gRPC channel, sends a `SubscribeRequest` with `STREAM` mode, receives `SubscribeResponse` notifications continuously. Uses `elixir-grpc` client with protobuf-compiled gNMI service stubs.
- **NetconfSession** -- GenServer per device. Opens SSH connection to port 830, invokes the `netconf` subsystem, exchanges XML RPCs (`<get>`, `<get-config>`, `create-subscription`). Parses responses with SweetXml.
- **DeviceManager** -- Orchestrates which devices this collector node is responsible for. Uses consistent hashing (via `hash_ring`) or database-based assignment with row-level locking.
- **Oban Workers** -- Device discovery, stale session cleanup, config backup jobs.

### Web Nodes (Phoenix)

**Purpose**: Serve interactive dashboards with real-time updates.

- **LiveView Dashboards** -- Users create custom dashboards composed of widgets. Each widget subscribes to PubSub topics for real-time data and queries TimescaleDB for historical ranges.
- **VegaLite/Tucan Charts** -- Client-side interactive rendering. Tucan's `lineplot` for time-series trends, `bar` for comparisons, `area` for bandwidth utilization, `scatter` for discrete events. JSON specs are pushed to the browser via LiveView hooks, rendered by the Vega JS runtime with built-in tooltips, zoom, and pan.
- **Dashboard Configuration** -- Stored in PostgreSQL. Users can add/remove/rearrange widgets, set time ranges, choose metrics and devices per widget.

### TimescaleDB

**Purpose**: Durable time-series storage with SQL query power.

- **Raw metrics hypertable** -- All incoming telemetry lands here. Partitioned by time (1-day chunks by default). Compressed after 7 days.
- **Continuous aggregates** -- Pre-computed 5-minute and 1-hour rollups that refresh automatically. Used for dashboard queries over longer time ranges.
- **Standard tables** -- Device inventory, dashboard configurations, user accounts.

## Data Flow

1. Network device emits telemetry (gNMI notification or NETCONF event)
2. Collector node's `GnmiSession` / `NetconfSession` receives it
3. Metric is normalized into `{time, device_id, path, tags, value}` tuples
4. Batch inserted into TimescaleDB `metrics` hypertable
5. Simultaneously broadcast via `Phoenix.PubSub.broadcast/3` to topic `"device:{device_id}"`
6. Web node's LiveView receives PubSub message, updates socket assigns
7. LiveView rebuilds VegaLite spec with new data, pushes it via `push_event/3` to the browser's Vega hook for re-render

## Technology Justification

| Technology | Why |
|---|---|
| **TimescaleDB** | PostgreSQL extension = works with Ecto/Postgrex out of the box. SQL for complex queries. Continuous aggregates for pre-computed rollups. Compression for cost efficiency. The `timescale` hex package adds migration helpers. |
| **VegaLite/Tucan** | Vega-Lite grammar of graphics via Elixir. Tucan provides high-level chart functions (`lineplot`, `bar`, `area`, `scatter`). Rich built-in interactivity (tooltips, zoom, pan, selections). Rendered client-side by Vega JS runtime. Temporal encoding handles timestamp axes natively. |
| **elixir-grpc** | Mature gRPC implementation (5M+ downloads). Supports bidirectional streaming needed for gNMI Subscribe. Mint and Gun HTTP/2 adapters. |
| **Erlang :ssh** | OTP ships with SSH client. Direct access to SSH subsystem invocation for NETCONF. No external dependency needed. |
| **Horde** | Distributed DynamicSupervisor ensures exactly one session per device across the cluster. Automatic failover when a collector node dies. |
| **libcluster** | Automatic BEAM node discovery. Supports DNS polling (Kubernetes), gossip (LAN), and EPMD strategies. |

## Scalability Strategy

- **Horizontal collector scaling**: Add more collector nodes. Devices are rebalanced automatically via consistent hashing or database assignment.
- **Horizontal web scaling**: Add more web nodes behind a load balancer. LiveView WebSocket connections are sticky to a node, but PubSub ensures all nodes receive all events.
- **Database scaling**: TimescaleDB read replicas for dashboard queries. Continuous aggregates reduce query load. Compression + retention policies manage storage growth.
- **Target**: 5,000+ devices, 100k+ metrics/second ingestion, sub-second dashboard updates.

## "Are TimescaleDB Reads Real-Time?"

**Yes.** TimescaleDB is PostgreSQL with a time-series extension. Regular SQL queries against the raw `metrics` hypertable return data as fast as any PostgreSQL query -- typically single-digit milliseconds for recent data (the most recent chunks are kept uncompressed in memory).

The distinction:
- **Raw queries** (`SELECT * FROM metrics WHERE time > now() - interval '5 minutes'`) -- fully real-time, returns whatever was just inserted
- **Continuous aggregates** (`SELECT * FROM metrics_5m WHERE bucket > now() - interval '1 hour'`) -- materialized views that refresh on a schedule (e.g., every 5 minutes). There's a lag equal to the refresh interval.

**For dashboards**, the architecture combines both:
- Real-time updates come via **PubSub** (zero lag, pushed from collector to browser)
- Historical chart data comes from **TimescaleDB queries** (real-time for raw data, near-real-time for aggregates)
- When a user first loads a dashboard or scrolls back in time, we query the DB
- While they're watching live, PubSub pushes new points directly
