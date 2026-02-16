# 06: Process Lifecycle & Supervision

## Supervision Tree

```
SwitchTelemetry.Supervisor (one_for_one)
├── SwitchTelemetry.Repo (Ecto)                          ← PostgreSQL connection pool
├── SwitchTelemetry.InfluxDB (Instream)                  ← InfluxDB v2 connection
├── SwitchTelemetry.Vault (Cloak)                        ← AES-256-GCM encryption at rest
├── {Phoenix.PubSub, name: SwitchTelemetry.PubSub}
├── {Horde.Registry, name: DistributedRegistry}          ← cluster-wide process names
├── {Horde.DynamicSupervisor, name: DistributedSupervisor} ← cluster-wide process supervisor
├── {Finch, name: SwitchTelemetry.Finch}                 ← HTTP client for webhooks/notifications
│
├── [COLLECTOR ONLY]
│   ├── SwitchTelemetry.Collector.DeviceAssignment       ← consistent hash ring for device ownership
│   ├── SwitchTelemetry.Collector.NodeMonitor             ← watches cluster membership
│   ├── SwitchTelemetry.Collector.DeviceManager           ← orchestrates device sessions
│   │   └── (dynamically starts GnmiSession / NetconfSession via Horde)
│   ├── SwitchTelemetry.Collector.StreamMonitor           ← tracks stream health and message rates
│   └── {Oban, queues: [...]}                             ← background jobs
│       ├── SwitchTelemetry.Workers.DeviceDiscovery       (queue: discovery)
│       ├── SwitchTelemetry.Workers.StaleSessionCleanup   (queue: maintenance)
│       ├── SwitchTelemetry.Workers.AlertEvaluator        (queue: alerts, cron: every minute)
│       ├── SwitchTelemetry.Workers.AlertNotifier          (queue: notifications)
│       └── SwitchTelemetry.Workers.AlertEventPruner       (queue: maintenance, cron: daily 3am)
│
└── [WEB ONLY]
    ├── SwitchTelemetryWeb.Telemetry                      ← :telemetry metrics
    └── SwitchTelemetryWeb.Endpoint                       ← Phoenix HTTP/WebSocket
```

## GenServer Usage Rules

GenServers are used for **infrastructure** processes, NOT for domain entities.

### Allowed GenServer Uses

| GenServer | Purpose | State Loss Impact |
|---|---|---|
| `GnmiSession` | Manages gRPC connection to a device | Reconnects automatically; no data lost (metrics already in DB) |
| `NetconfSession` | Manages SSH/NETCONF connection | Reconnects automatically |
| `DeviceManager` | Tracks which devices this node owns | Rebuilt from DB on restart |
| `DeviceAssignment` | Consistent hash ring for device ownership | Rebuilt from node list on restart |
| `NodeMonitor` | Watches cluster membership changes | Stateless (reacts to events) |
| `StreamMonitor` | Tracks stream health, message rates, errors | Rebuilt from live session reports; no persistent state |

### Prohibited GenServer Uses

- **Do NOT** store metric data in GenServer state (write to InfluxDB)
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

## Oban Workers

Oban runs only on collector nodes (or `NODE_ROLE=both`). Web-only nodes set `queues: false`.

### Queues

| Queue | Concurrency | Purpose |
|---|---|---|
| `discovery` | 2 | Device discovery and assignment |
| `maintenance` | 1 | Session cleanup, alert event pruning |
| `alerts` | 1 | Alert rule evaluation |
| `notifications` | 5 | Alert notification delivery (webhook, Slack, email) |

### Workers

| Worker | Queue | Schedule | Description |
|---|---|---|---|
| `DeviceDiscovery` | `discovery` | On-demand | Finds unassigned devices, assigns them to collectors via hash ring, detects stale heartbeats |
| `StaleSessionCleanup` | `maintenance` | On-demand | Detects Horde-registered sessions on dead nodes, cleans up and triggers rebalance |
| `AlertEvaluator` | `alerts` | `* * * * *` (every minute) | Evaluates all enabled alert rules against recent metrics, creates alert events, enqueues notifications |
| `AlertNotifier` | `notifications` | On-demand (enqueued by AlertEvaluator) | Delivers notifications via Finch (webhook/Slack) or Swoosh (email); max 5 attempts |
| `AlertEventPruner` | `maintenance` | `0 3 * * *` (daily at 3:00 AM UTC) | Deletes alert events older than 30 days, keeping at least 100 per rule |

### Cron Plugin

Configured in `config/config.exs`:

```elixir
plugins: [
  {Oban.Plugins.Cron,
   crontab: [
     {"* * * * *", SwitchTelemetry.Workers.AlertEvaluator},
     {"0 3 * * *", SwitchTelemetry.Workers.AlertEventPruner}
   ]}
]
```

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
