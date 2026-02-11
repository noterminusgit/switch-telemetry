# 06: Process Lifecycle & Supervision

## Supervision Tree

```
SwitchTelemetry.Supervisor (one_for_one)
├── SwitchTelemetry.Repo (Ecto)
├── {Phoenix.PubSub, name: SwitchTelemetry.PubSub}
├── {Cluster.Supervisor, topologies}                    ← libcluster
├── {Horde.Registry, name: DistributedRegistry}         ← cluster-wide process names
├── {Horde.DynamicSupervisor, name: DistributedSupervisor} ← cluster-wide process supervisor
│
├── [COLLECTOR ONLY]
│   ├── SwitchTelemetry.Collector.DeviceManager         ← orchestrates device sessions
│   │   └── (dynamically starts GnmiSession / NetconfSession via Horde)
│   ├── SwitchTelemetry.Collector.NodeMonitor            ← watches cluster membership
│   └── {Oban, queues: [...]}                            ← background jobs
│       ├── SwitchTelemetry.Workers.DeviceDiscovery
│       ├── SwitchTelemetry.Workers.StaleSessionCleanup
│       └── SwitchTelemetry.Workers.ConfigBackup
│
└── [WEB ONLY]
    ├── SwitchTelemetryWeb.Telemetry                     ← :telemetry metrics
    ├── SwitchTelemetryWeb.Endpoint                      ← Phoenix HTTP/WebSocket
    └── SwitchTelemetryWeb.Presence                      ← user presence tracking
```

## GenServer Usage Rules

GenServers are used for **infrastructure** processes, NOT for domain entities.

### Allowed GenServer Uses

| GenServer | Purpose | State Loss Impact |
|---|---|---|
| `GnmiSession` | Manages gRPC connection to a device | Reconnects automatically; no data lost (metrics already in DB) |
| `NetconfSession` | Manages SSH/NETCONF connection | Reconnects automatically |
| `DeviceManager` | Tracks which devices this node owns | Rebuilt from DB on restart |
| `DeviceAssignment` | Consistent hash ring | Rebuilt from node list on restart |
| `NodeMonitor` | Watches cluster membership changes | Stateless (reacts to events) |

### Prohibited GenServer Uses

- **Do NOT** store metric data in GenServer state (write to TimescaleDB)
- **Do NOT** store dashboard configs in GenServer state (query from PostgreSQL)
- **Do NOT** cache device inventory in GenServer state long-term (query from PostgreSQL, use ETS for short-lived cache if needed)

## Device Session Lifecycle

```
          DeviceManager
               │
               │ start_device_session(device)
               ▼
     Horde.DynamicSupervisor
               │
               │ start_child(GnmiSession or NetconfSession)
               ▼
     ┌─────────────────┐
     │   init/1        │
     │  send(:connect) │
     └────────┬────────┘
              │
              ▼
     ┌─────────────────┐     failure     ┌──────────────────┐
     │   :connect      │────────────────►│  schedule_retry  │
     │  SSH/gRPC open  │                 │  (exp. backoff)  │
     └────────┬────────┘                 └────────┬─────────┘
              │ success                           │
              ▼                                   │
     ┌─────────────────┐                          │
     │  :subscribe     │◄─────────────────────────┘
     │  (gNMI) or      │
     │  :collect loop   │
     │  (NETCONF)      │
     └────────┬────────┘
              │
              ▼
     ┌─────────────────────────────────┐
     │  Steady State                   │
     │                                 │
     │  gNMI: Task reads stream,       │
     │    calls insert_batch +         │
     │    PubSub.broadcast per         │
     │    notification                 │
     │                                 │
     │  NETCONF: :collect timer fires, │
     │    sends XML RPC, parses        │
     │    response, inserts + broadcasts│
     └────────┬────────────────────────┘
              │
              │ connection lost / stream ended
              ▼
     ┌─────────────────┐
     │  Reconnect      │
     │  (back to       │
     │   :connect)     │
     └─────────────────┘
```

## Failover Behavior

When a collector node crashes:

1. Erlang distribution detects the node is down (via `net_kernel.monitor_nodes`)
2. `NodeMonitor` on surviving collectors receives `{:nodedown, node, _info}`
3. Horde detects member loss and restarts orphaned processes on surviving nodes
4. `DeviceAssignment` rebuilds the hash ring without the failed node
5. Device sessions that were on the failed node are restarted on new owners
6. Sessions reconnect to devices and resume telemetry collection
7. PubSub subscriptions on web nodes continue working (they don't care which collector sends the broadcast)

**Typical failover time**: 5-15 seconds (Horde redistribution + gRPC/SSH reconnection)

## Telemetry & Health Checks

```elixir
defmodule SwitchTelemetryWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Collector metrics
      counter("switch_telemetry.collector.metrics_ingested.count",
        tags: [:device_id, :source]),
      summary("switch_telemetry.collector.ingest_batch.duration",
        unit: {:native, :millisecond}),
      last_value("switch_telemetry.collector.active_sessions.count"),
      last_value("switch_telemetry.collector.devices_assigned.count"),

      # Database metrics
      summary("switch_telemetry.repo.query.total_time",
        unit: {:native, :millisecond}),

      # Phoenix metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}),
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond})
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :collector_session_count, []},
      {__MODULE__, :cluster_node_count, []}
    ]
  end

  def collector_session_count do
    count = Horde.Registry.count(SwitchTelemetry.DistributedRegistry)
    :telemetry.execute(
      [:switch_telemetry, :collector, :active_sessions],
      %{count: count}
    )
  end

  def cluster_node_count do
    :telemetry.execute(
      [:switch_telemetry, :cluster, :nodes],
      %{count: length(Node.list()) + 1}
    )
  end
end
```
