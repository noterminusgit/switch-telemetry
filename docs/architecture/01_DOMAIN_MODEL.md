# 01: Domain Model

## Core Entities

### Device

Represents a network device (switch, router, firewall) that we collect telemetry from.

```elixir
%SwitchTelemetry.Devices.Device{
  id: "dev_01HQBMB5KTQNDRPQHM3VX",       # ULID with prefix
  hostname: "core-sw-01.dc1.example.com",
  ip_address: "10.0.1.1",
  platform: :cisco_iosxr,                   # :cisco_iosxr | :cisco_nxos | :juniper_junos | :arista_eos | :nokia_sros
  transport: :gnmi,                          # :gnmi | :netconf | :both
  gnmi_port: 57400,
  netconf_port: 830,
  credentials_id: "cred_01HQBMA5KT",        # FK to encrypted credentials
  tags: %{"site" => "dc1", "role" => "core", "vendor" => "cisco"},
  collection_interval_ms: 30_000,
  status: :active,                           # :active | :inactive | :unreachable | :maintenance
  assigned_collector: "collector1@10.0.0.5", # node name of assigned collector
  collector_heartbeat: ~U[2024-01-15 10:30:00Z],
  last_seen_at: ~U[2024-01-15 10:30:00Z],
  inserted_at: ~U[2024-01-01 00:00:00Z],
  updated_at: ~U[2024-01-15 10:30:00Z]
}
```

### Metric (InfluxDB measurement)

A single telemetry data point. Stored in InfluxDB's `metrics_raw` bucket as a measurement named `"metrics"`.

```elixir
# Conceptual representation (stored in InfluxDB, not an Ecto schema)
%{
  time: ~U[2024-01-15 10:30:00.123456Z],    # NOT NULL, nanosecond precision
  device_id: "dev_01HQBMB5KTQNDRPQHM3VX",  # tag (indexed)
  path: "/interfaces/interface[name=Ethernet1/1]/state/counters/in-octets",  # tag
  source: :gnmi,                              # tag: :gnmi | :netconf
  value_float: 1_234_567.89,                 # field: used for gauges, rates
  value_int: nil,                            # field: used for counters, discrete values
  value_str: nil                             # field: used for state strings ("up", "down")
}
```

**Why three value fields (medium layout)?**
Network telemetry is heterogeneous -- interface counters are integers, CPU utilization is a float, interface admin-status is a string. A single `value` field would require type coercion and lose precision. The medium layout keeps proper types while allowing new metrics without schema changes. In InfluxDB, unused fields simply don't appear in the line protocol point (no storage cost).

### Subscription

Defines what telemetry paths to collect from a device.

```elixir
%SwitchTelemetry.Collector.Subscription{
  id: "sub_01HQBMB5KTQNDRPQHM3VX",
  device_id: "dev_01HQBMB5KTQNDRPQHM3VX",
  paths: [
    "/interfaces/interface/state/counters",
    "/system/cpu/state",
    "/system/memory/state",
    "/network-instances/network-instance/protocols/protocol/bgp/neighbors/neighbor/state"
  ],
  mode: :stream,                             # :stream | :poll | :once (gNMI modes)
  sample_interval_ns: 30_000_000_000,        # 30 seconds in nanoseconds (gNMI convention)
  encoding: :proto,                          # :proto | :json | :json_ietf (gNMI encoding)
  enabled: true,
  inserted_at: ~U[2024-01-01 00:00:00Z],
  updated_at: ~U[2024-01-01 00:00:00Z]
}
```

### Dashboard

User-created dashboard configuration.

```elixir
%SwitchTelemetry.Dashboards.Dashboard{
  id: "dash_01HQBMB5KTQNDRPQHM3VX",
  user_id: "usr_01HQBMA5KT",
  name: "DC1 Core Switches",
  description: "Real-time monitoring of datacenter core layer",
  layout: :grid,                             # :grid | :freeform
  refresh_interval_ms: 5_000,
  is_public: true,
  widgets: [                                  # ordered list of widget configs
    %Widget{...},
    %Widget{...}
  ],
  inserted_at: ~U[2024-01-01 00:00:00Z],
  updated_at: ~U[2024-01-15 10:30:00Z]
}
```

### Widget

A single chart/display element within a dashboard.

```elixir
%SwitchTelemetry.Dashboards.Widget{
  id: "wgt_01HQBMB5KTQNDRPQHM3VX",
  dashboard_id: "dash_01HQBMB5KTQNDRPQHM3VX",
  title: "Interface Utilization - Ethernet1/1",
  chart_type: :line,                          # :line | :bar | :area | :points | :gauge | :table
  position: %{x: 0, y: 0, w: 6, h: 4},     # grid position and size
  time_range: %{
    type: :relative,                          # :relative | :absolute
    duration: "1h"                            # "5m" | "1h" | "24h" | "7d"
  },
  queries: [                                  # what data to display
    %{
      device_id: "dev_01HQBMB5KTQNDRPQHM3VX",
      path: "/interfaces/interface[name=Ethernet1/1]/state/counters/in-octets",
      aggregation: :rate,                     # :raw | :rate | :avg | :max | :min | :sum
      bucket_size: "1m",                      # time_bucket size
      label: "Inbound Traffic",
      color: "#3B82F6"
    },
    %{
      device_id: "dev_01HQBMB5KTQNDRPQHM3VX",
      path: "/interfaces/interface[name=Ethernet1/1]/state/counters/out-octets",
      aggregation: :rate,
      bucket_size: "1m",
      label: "Outbound Traffic",
      color: "#EF4444"
    }
  ],
  inserted_at: ~U[2024-01-01 00:00:00Z],
  updated_at: ~U[2024-01-15 10:30:00Z]
}
```

### Credential

Encrypted device authentication credentials.

```elixir
%SwitchTelemetry.Devices.Credential{
  id: "cred_01HQBMA5KT",
  name: "DC1 Switch Credentials",
  username: "telemetry_ro",                   # plaintext (read-only service account)
  password: <<encrypted>>,                    # encrypted at rest (Cloak.Ecto)
  ssh_key: <<encrypted>>,                     # optional, for NETCONF key-based auth
  tls_cert: <<encrypted>>,                    # optional, for gNMI mTLS
  tls_key: <<encrypted>>,
  inserted_at: ~U[2024-01-01 00:00:00Z],
  updated_at: ~U[2024-01-01 00:00:00Z]
}
```

## Relationships

```
Credential  1 ──── * Device
Device      1 ──── * Subscription
Device      1 ──── * Metric (InfluxDB)
Dashboard   1 ──── * Widget
User        1 ──── * Dashboard
```

## Business Rules

1. A device can have both gNMI and NETCONF transports (`transport: :both`), but each transport gets its own session GenServer.
2. Subscriptions are per-device. Multiple paths can be batched into a single gNMI SubscribeRequest.
3. Metrics are append-only. Never update or delete individual data points (InfluxDB manages retention via bucket policies).
4. Dashboard widgets can reference metrics from multiple devices (e.g., compare bandwidth across uplinks).
5. Only collector nodes write to the InfluxDB `metrics_raw` bucket. Web nodes only read.
6. Device assignment is exclusive -- exactly one collector node owns a device at any time.

## State Machines

### Device Status

```
                 ┌──────────┐
     ┌──────────►│  active   │◄──────────┐
     │           └─────┬─────┘           │
     │                 │                 │
     │           connection              │
     │            failure            reconnect
     │                 │              success
     │                 ▼                 │
     │          ┌──────────────┐         │
     │          │ unreachable  ├─────────┘
     │          └──────────────┘
     │
  activate            deactivate
     │                    │
     │           ┌────────▼───┐
     └───────────┤  inactive   │
     │           └─────────────┘
     │
     │           ┌──────────────┐
     └───────────┤ maintenance  │
                 └──────────────┘
```

Transitions:
- `active -> unreachable`: connection lost or 3 consecutive collection failures
- `unreachable -> active`: successful reconnection
- `active -> inactive`: administrator disables collection
- `inactive -> active`: administrator enables collection
- `active -> maintenance`: administrator puts device in maintenance window
- `maintenance -> active`: maintenance window ends
