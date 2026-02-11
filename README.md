# Switch Telemetry

A distributed network telemetry collection and visualization platform built with Elixir, Phoenix LiveView, and TimescaleDB.

## Overview

Switch Telemetry is a modular platform for collecting, storing, and visualizing network device telemetry at scale. It connects to thousands of network devices using **gNMI** (gRPC Network Management Interface) and **NETCONF** (RFC 6241) protocols, persists time-series metrics in **TimescaleDB**, and serves interactive dashboards via **Phoenix LiveView** with **VegaLite/Tucan** interactive charting.

The system is designed to scale horizontally by separating data collection and UI workloads across different BEAM VM nodes within a single distributed cluster.

## Architecture

This project follows Dave Thomas's multi-app structure with path-based dependencies:

```
switch_telemetry/
├── switch_telemetry_core/      # Domain logic, Ecto schemas, TimescaleDB queries
├── switch_telemetry_collector/  # gNMI + NETCONF protocol clients, device sessions
├── switch_telemetry_web/        # Phoenix LiveView dashboards, VegaLite/Tucan charts
└── switch_telemetry_jobs/       # Oban workers for async operations
```

### Node Types

The codebase produces two distinct Mix release targets:

- **Collector nodes** -- headless BEAM VMs that maintain gRPC streams and SSH/NETCONF sessions to network devices, writing telemetry to TimescaleDB and broadcasting updates via Phoenix.PubSub
- **Web nodes** -- Phoenix LiveView servers that serve modular dashboards, subscribe to real-time PubSub broadcasts, and query TimescaleDB for historical data

All nodes form a single BEAM cluster via `libcluster`, enabling transparent PubSub messaging across node boundaries.

```
                    +-----------+
                    |   Load    |
                    | Balancer  |
                    +-----+-----+
                          |
              +-----------+-----------+
              |                       |
        +-----+------+        +------+-----+
        | Web Node 1 |        | Web Node 2 |
        +-----+------+        +------+-----+
              |                       |
              +------ BEAM Cluster ---+----------+
              |                       |          |
        +-----+------+   +-----+------+  +------+-----+
        | Collector 1|   | Collector 2|  | Collector 3|
        +-----+------+   +-----+------+  +------+-----+
              |                 |                |
        [gNMI/NETCONF]   [gNMI/NETCONF]  [gNMI/NETCONF]
              |                 |                |
              +---------+------+-------+--------+
                        |              |
                  +-----+-----+ +-----+-----+
                  | TimescaleDB| |TimescaleDB|
                  |  (primary) | | (replica) |
                  +------------+ +-----------+
```

## Tech Stack

- **Elixir** 1.17+ / OTP 27+
- **Phoenix** 1.7+ / LiveView 1.0+ -- real-time web dashboards
- **VegaLite** 0.1+ / **Tucan** 0.5+ -- interactive client-side charting (Vega-Lite grammar of graphics)
- **TimescaleDB** 2.x -- time-series storage (PostgreSQL extension)
- **Ecto** 3.x + `timescale` hex package -- database layer
- **gRPC** (`grpc` hex package) + `protobuf` -- gNMI protocol client
- **Erlang :ssh** -- NETCONF over SSH (port 830)
- **SweetXml** -- XPath queries on NETCONF XML responses
- **libcluster** -- BEAM node discovery and clustering
- **Horde** -- distributed process registry/supervisor
- **Oban** -- background job processing
- **Phoenix.PubSub** (`:pg` adapter) -- cross-node event broadcasting

## Getting Started

```bash
# Prerequisites
# - Elixir 1.17+, Erlang/OTP 27+
# - PostgreSQL 16+ with TimescaleDB extension
# - protoc (protocol buffer compiler)

# Setup
mix deps.get
mix ecto.setup

# Generate gNMI proto modules
mix grpc.gen proto/gnmi.proto --out lib/switch_telemetry_collector/gnmi/

# Run in development (single node, both roles)
mix phx.server

# Build production releases
MIX_ENV=prod mix release collector
MIX_ENV=prod mix release web
```

## Documentation

See `docs/` directory for comprehensive architecture documentation:

- `docs/architecture/` -- System design, domain model, data layer, process architecture
- `docs/decisions/` -- Architecture Decision Records (ADRs)
- `docs/guardrails/` -- Coding standards, review checklists, role definitions
- `docs/HANDOFF.md` -- Quick-start guide for AI agent collaboration
