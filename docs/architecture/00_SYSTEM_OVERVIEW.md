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
    ┌──────────────────┐     ┌──────────────────┐
    │   InfluxDB v2    │     │   PostgreSQL     │
    │  (time-series)   │     │  (relational)    │
    │                  │     │                  │
    │  ┌────────────┐  │     │  ┌────────────┐  │
    │  │ metrics_raw│  │     │  │ devices    │  │
    │  │ (30d ret.) │  │     │  ├────────────┤  │
    │  ├────────────┤  │     │  │ dashboards │  │
    │  │ metrics_5m │  │     │  ├────────────┤  │
    │  │ (180d ret.)│  │     │  │ users      │  │
    │  ├────────────┤  │     │  ├────────────┤  │
    │  │ metrics_1h │  │     │  │ alert_rules│  │
    │  │ (730d ret.)│  │     │  ├────────────┤  │
    │  └────────────┘  │     │  │ oban_jobs  │  │
    └──────────────────┘     │  └────────────┘  │
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

- **LiveView Dashboards** -- Users create custom dashboards composed of widgets. Each widget subscribes to PubSub topics for real-time data and queries InfluxDB for historical ranges.
- **VegaLite/Tucan Charts** -- Client-side interactive rendering. Tucan's `lineplot` for time-series trends, `bar` for comparisons, `area` for bandwidth utilization, `scatter` for discrete events. JSON specs are pushed to the browser via LiveView hooks, rendered by the Vega JS runtime with built-in tooltips, zoom, and pan.
- **Dashboard Configuration** -- Stored in PostgreSQL. Users can add/remove/rearrange widgets, set time ranges, choose metrics and devices per widget.

### InfluxDB v2

**Purpose**: Durable time-series storage with Flux query language.

- **metrics_raw bucket** (30d retention) -- All incoming telemetry lands here via line protocol. Tagged by device_id, path, source. Fields: value_float, value_int, value_str.
- **metrics_5m bucket** (180d retention) -- 5-minute downsampled aggregates (avg, max, min, count). Populated by a Flux task running every 5 minutes.
- **metrics_1h bucket** (730d retention) -- 1-hour downsampled aggregates. Populated by a Flux task running hourly.

### PostgreSQL

**Purpose**: Relational data storage.

- **Standard tables** -- Device inventory, dashboard configurations, user accounts, alert rules/events, notification channels, Oban job queue.

## Data Flow

1. Network device emits telemetry (gNMI notification or NETCONF event)
2. Collector node's `GnmiSession` / `NetconfSession` receives it
3. Metric is normalized into `{time, device_id, path, tags, value}` tuples
4. Batch inserted into InfluxDB `metrics_raw` bucket via line protocol
5. Simultaneously broadcast via `Phoenix.PubSub.broadcast/3` to topic `"device:{device_id}"`
6. Web node's LiveView receives PubSub message, updates socket assigns
7. LiveView rebuilds VegaLite spec with new data, pushes it via `push_event/3` to the browser's Vega hook for re-render

## Technology Justification

| Technology | Why |
|---|---|
| **InfluxDB v2** | Purpose-built time-series database. Flux query language with native aggregation and downsampling. Built-in bucket retention policies. Open source for self-hosted use. The `instream` hex package provides an Elixir client. |
| **PostgreSQL** | Standard relational database for device inventory, dashboards, users, alerts, and Oban jobs. Works with Ecto/Postgrex out of the box. |
| **VegaLite/Tucan** | Vega-Lite grammar of graphics via Elixir. Tucan provides high-level chart functions (`lineplot`, `bar`, `area`, `scatter`). Rich built-in interactivity (tooltips, zoom, pan, selections). Rendered client-side by Vega JS runtime. Temporal encoding handles timestamp axes natively. |
| **elixir-grpc** | Mature gRPC implementation (5M+ downloads). Supports bidirectional streaming needed for gNMI Subscribe. Mint and Gun HTTP/2 adapters. |
| **Erlang :ssh** | OTP ships with SSH client. Direct access to SSH subsystem invocation for NETCONF. No external dependency needed. |
| **Horde** | Distributed DynamicSupervisor ensures exactly one session per device across the cluster. Automatic failover when a collector node dies. |
| **libcluster** | Automatic BEAM node discovery. Supports DNS polling (Kubernetes), gossip (LAN), and EPMD strategies. |

## Scalability Strategy

- **Horizontal collector scaling**: Add more collector nodes. Devices are rebalanced automatically via consistent hashing or database assignment.
- **Horizontal web scaling**: Add more web nodes behind a load balancer. LiveView WebSocket connections are sticky to a node, but PubSub ensures all nodes receive all events.
- **Database scaling**: InfluxDB handles time-series reads/writes independently of PostgreSQL. Downsampled buckets (5m, 1h) reduce query load for longer ranges. Retention policies manage storage growth automatically.
- **Target**: 5,000+ devices, 100k+ metrics/second ingestion, sub-second dashboard updates.

## InfluxDB Query Latency

**Raw bucket queries are near-real-time.** Data written via line protocol is queryable within milliseconds. InfluxDB's TSM storage engine is optimized for recent time-series reads.

The distinction:
- **Raw queries** (`from(bucket: "metrics_raw") |> range(start: -5m)`) -- returns whatever was just written, single-digit millisecond latency for recent data
- **Downsampled queries** (`from(bucket: "metrics_5m")`) -- populated by Flux tasks on a schedule (every 5 minutes). There's a lag equal to the task interval.

**For dashboards**, the architecture combines both:
- Real-time updates come via **PubSub** (zero lag, pushed from collector to browser)
- Historical chart data comes from **InfluxDB Flux queries** (raw bucket for short ranges, downsampled buckets for longer ranges)
- When a user first loads a dashboard or scrolls back in time, we query InfluxDB
- While they're watching live, PubSub pushes new points directly
