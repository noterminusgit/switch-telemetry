# 04: Distributed Architecture

## Node Separation Strategy

The application produces two Mix release targets from a single codebase. The `NODE_ROLE` environment variable controls which supervision children start on each node.

### Mix Releases

```elixir
# mix.exs
def project do
  [
    app: :switch_telemetry,
    releases: [
      collector: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble]
      ],
      web: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, &copy_assets/1]
      ]
    ]
  ]
end
```

### Conditional Supervision Tree

```elixir
defmodule SwitchTelemetry.Application do
  use Application

  @impl true
  def start(_type, _args) do
    node_role = System.get_env("NODE_ROLE", "both")

    children =
      common_children() ++
      collector_children(node_role) ++
      web_children(node_role)

    opts = [strategy: :one_for_one, name: SwitchTelemetry.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Always started on every node type
  defp common_children do
    [
      SwitchTelemetry.Repo,
      {Phoenix.PubSub, name: SwitchTelemetry.PubSub},
      {Cluster.Supervisor, [topologies(), [name: SwitchTelemetry.ClusterSupervisor]]},
      {Horde.Registry, [name: SwitchTelemetry.DistributedRegistry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor, [name: SwitchTelemetry.DistributedSupervisor, strategy: :one_for_one, members: :auto]}
    ]
  end

  # Only on collector nodes
  defp collector_children(role) when role in ["collector", "both"] do
    [
      SwitchTelemetry.Collector.DeviceManager,
      SwitchTelemetry.Collector.NodeMonitor,
      {Oban, Application.fetch_env!(:switch_telemetry, Oban)}
    ]
  end
  defp collector_children(_), do: []

  # Only on web nodes
  defp web_children(role) when role in ["web", "both"] do
    [
      SwitchTelemetryWeb.Telemetry,
      SwitchTelemetryWeb.Endpoint,
      SwitchTelemetryWeb.Presence
    ]
  end
  defp web_children(_), do: []

  defp topologies do
    Application.get_env(:libcluster, :topologies, [])
  end
end
```

### Runtime Configuration

```elixir
# config/runtime.exs
import Config

node_role = System.get_env("NODE_ROLE", "both")

# Database -- all nodes connect
config :switch_telemetry, SwitchTelemetry.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: if(node_role == "collector", do: 20, else: 10)

# libcluster -- all nodes join the same cluster
config :libcluster,
  topologies: [
    dns_poll: [
      strategy: Cluster.Strategy.DNSPoll,
      config: [
        polling_interval: 5_000,
        query: System.get_env("CLUSTER_DNS", "switch-telemetry.internal"),
        node_basename: System.get_env("RELEASE_NAME", "switch_telemetry")
      ]
    ]
  ]

# Oban -- only on collector nodes
if node_role in ["collector", "both"] do
  config :switch_telemetry, Oban,
    repo: SwitchTelemetry.Repo,
    queues: [
      discovery: 2,
      maintenance: 1,
      config_backup: 1
    ]
end

# Phoenix endpoint -- only on web nodes
if node_role in ["web", "both"] do
  config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST", "localhost")],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    secret_key_base: System.get_env("SECRET_KEY_BASE"),
    server: true
end
```

## Cluster Formation

### libcluster Topology Strategies

| Strategy | Environment | How It Works |
|---|---|---|
| `DNSPoll` | Kubernetes, Fly.io | Polls a DNS name that resolves to all pod IPs |
| `Gossip` | LAN, development | Multicast UDP gossip |
| `EPMD` | Static hosts | Connect to known hostnames via Erlang Port Mapper |
| `Kubernetes` | Kubernetes | Uses K8s API to discover pods by label selector |

All node types (collector + web) join the **same cluster** so that Phoenix.PubSub messages flow transparently between them.

### PubSub Across Nodes

Phoenix.PubSub with the default `:pg` adapter (Erlang process groups) works automatically across all connected BEAM nodes. No configuration needed beyond starting PubSub on every node.

```
  Collector 1          Collector 2          Web 1            Web 2
  ┌──────────┐         ┌──────────┐       ┌──────────┐    ┌──────────┐
  │ PubSub   │         │ PubSub   │       │ PubSub   │    │ PubSub   │
  │ :pg group├─────────┤ :pg group├───────┤ :pg group├────┤ :pg group│
  └────┬─────┘         └──────────┘       └────┬─────┘    └────┬─────┘
       │                                       │               │
  broadcast(                              subscribe(       subscribe(
   "device:X",                            "device:X")      "device:X")
   {:metrics, data})                           │               │
       │                                  LiveView A       LiveView B
       └──────────────────────────────────────►│               │
                                               └───────────────┘
                                           Both receive the broadcast
```

## Device Assignment

### Consistent Hashing (Recommended)

```elixir
# deps: {:hash_ring, "~> 0.4"}

defmodule SwitchTelemetry.Collector.DeviceAssignment do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    ring = rebuild_ring()
    {:ok, %{ring: ring}}
  end

  def get_owner(device_id) do
    GenServer.call(__MODULE__, {:get_owner, device_id})
  end

  @impl true
  def handle_call({:get_owner, device_id}, _from, state) do
    node = HashRing.key_to_node(state.ring, device_id)
    {:reply, node, state}
  end

  @impl true
  def handle_info({:nodeup, _node, _info}, state) do
    {:noreply, %{state | ring: rebuild_ring()}}
  end

  def handle_info({:nodedown, _node, _info}, state) do
    {:noreply, %{state | ring: rebuild_ring()}}
  end

  defp rebuild_ring do
    [Node.self() | Node.list()]
    |> Enum.filter(&collector_node?/1)
    |> then(&HashRing.new/1)
  end

  defp collector_node?(node) do
    node |> Atom.to_string() |> String.starts_with?("collector")
  end
end
```

When a collector node joins or leaves, only ~1/N of devices need to be reassigned (where N is the number of collector nodes). This is much better than round-robin redistribution.

## Deployment Topologies

### Docker Compose (Development)

```yaml
services:
  db:
    image: timescale/timescaledb:latest-pg16
    environment:
      POSTGRES_DB: switch_telemetry_dev
      POSTGRES_PASSWORD: postgres
    ports: ["5432:5432"]

  collector1:
    build: {context: ., args: {RELEASE_TYPE: collector}}
    environment:
      NODE_ROLE: collector
      DATABASE_URL: ecto://postgres:postgres@db/switch_telemetry_dev
      RELEASE_NODE: collector1@collector1
      CLUSTER_DNS: switch-telemetry.internal
    depends_on: [db]

  collector2:
    build: {context: ., args: {RELEASE_TYPE: collector}}
    environment:
      NODE_ROLE: collector
      DATABASE_URL: ecto://postgres:postgres@db/switch_telemetry_dev
      RELEASE_NODE: collector2@collector2
      CLUSTER_DNS: switch-telemetry.internal
    depends_on: [db]

  web:
    build: {context: ., args: {RELEASE_TYPE: web}}
    environment:
      NODE_ROLE: web
      DATABASE_URL: ecto://postgres:postgres@db/switch_telemetry_dev
      RELEASE_NODE: web1@web
      CLUSTER_DNS: switch-telemetry.internal
      SECRET_KEY_BASE: <generate-with-mix-phx-gen-secret>
    ports: ["4000:4000"]
    depends_on: [db]
```

### Kubernetes (Production)

See `docs/architecture/00_SYSTEM_OVERVIEW.md` for the full K8s manifest pattern. Key points:

- **Headless Service** for cluster discovery (all node types share one service)
- **Separate Deployments** for collector and web (different replica counts)
- **LoadBalancer Service** only for web nodes
- libcluster `Kubernetes` strategy with label selector matching both deployments

### Fly.io

- Two separate Fly apps sharing a private network
- `fly networks attach` to connect them
- DNSPoll strategy using `*.internal` DNS names
