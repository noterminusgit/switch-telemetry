# ADR-002: Separate Collector and Web Node Types

**Status:** Accepted
**Date:** 2026-02-10

## Context

The system must scale to thousands of devices while serving interactive dashboards. Device collection (gRPC streams, SSH sessions) is resource-intensive and long-lived. Web serving (LiveView, SVG rendering) is latency-sensitive. Running both on the same node creates resource contention.

## Decision

Produce two Mix release types (`collector` and `web`) from a single codebase. Use `NODE_ROLE` environment variable to conditionally start supervision children. All nodes join the same BEAM cluster via `libcluster`.

## Rationale

- **Independent scaling**: Add more collector nodes when device count grows. Add more web nodes when dashboard users increase. Each workload scales independently.
- **Resource isolation**: Collector nodes can be CPU/memory-optimized for maintaining thousands of concurrent gRPC/SSH connections. Web nodes can be optimized for low-latency HTTP/WebSocket serving.
- **Single codebase**: Both releases share the same Ecto schemas, PubSub config, and business logic. No code duplication.
- **BEAM clustering**: Phoenix.PubSub with the `:pg` adapter works transparently across all connected nodes. A collector broadcasting metrics is received by all web nodes automatically.
- **Graceful degradation**: If all collector nodes go down, web nodes still serve cached/historical data from TimescaleDB. If all web nodes go down, collectors continue ingesting.

## Alternatives Considered

### Single Node Type (monolith)
**Pros**: Simpler deployment, no clustering needed.
**Cons**: Can't scale collection and serving independently. A spike in dashboard users slows down telemetry ingestion.
**Rejected**: Won't scale beyond ~500 devices on a single node.

### Separate Applications (microservices)
**Pros**: Complete isolation, independent deployment.
**Cons**: Lose BEAM distribution benefits. Need an external message broker (Kafka, RabbitMQ) for real-time updates. More complex deployment and versioning.
**Rejected**: The BEAM cluster gives us PubSub, Horde, and RPC for free. A message broker adds latency and operational burden.

## Consequences

### Positive
- True horizontal scaling for both workloads
- PubSub-based real-time updates with zero additional infrastructure
- Development mode runs as single node (`NODE_ROLE=both`) for simplicity

### Negative
- Must manage BEAM clustering (libcluster, epmd, network policies)
- Two Docker images or release artifacts to build and deploy
- Debugging distributed issues requires understanding BEAM distribution
