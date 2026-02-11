# Phase 5 Design: Alerting & Notifications

## Overview

Add threshold-based alerting on telemetry metrics with configurable notification channels. Operators define alert rules that evaluate against incoming metrics. When a rule fires, notifications are dispatched to configured channels (webhook, Slack, email). Alert events are persisted for audit and displayed in real-time on dashboards.

## Domain Model

### AlertRule

Defines a condition to evaluate against metrics.

```elixir
%AlertRule{
  id: "alr_...",
  name: "Core Router CPU High",
  description: "CPU utilization exceeds 90% for 5 minutes",
  device_id: "dev_...",          # nil = all devices
  path: "openconfig-system:system/cpus/cpu/state/total/instant",
  condition: :above,             # :above | :below | :absent | :rate_increase
  threshold: 90.0,
  duration_seconds: 300,         # sustained for this long before firing
  cooldown_seconds: 600,         # don't re-fire within this window
  severity: :critical,           # :info | :warning | :critical
  enabled: true,
  state: :ok,                    # :ok | :firing | :acknowledged
  last_fired_at: ~U[...],
  last_resolved_at: ~U[...],
  inserted_at: ~U[...],
  updated_at: ~U[...]
}
```

**Condition types:**
- `:above` — `value_float > threshold`
- `:below` — `value_float < threshold`
- `:absent` — no metric received for `duration_seconds`
- `:rate_increase` — rate of change over `duration_seconds` exceeds `threshold` (per-second rate)

### AlertEvent

Immutable log of every alert state change.

```elixir
%AlertEvent{
  id: "ale_...",
  alert_rule_id: "alr_...",
  device_id: "dev_...",
  status: :firing,               # :firing | :resolved | :acknowledged
  value: 94.7,                   # metric value that triggered it
  message: "CPU at 94.7% (threshold: 90.0%)",
  metadata: %{},                 # extra context (path, tags, etc.)
  inserted_at: ~U[...]
}
```

### NotificationChannel

A destination for alert notifications.

```elixir
%NotificationChannel{
  id: "nch_...",
  name: "Ops Slack",
  type: :slack,                  # :webhook | :slack | :email
  config: %{                     # type-dependent config
    "url" => "https://hooks.slack.com/services/...",
  },
  enabled: true,
  inserted_at: ~U[...],
  updated_at: ~U[...]
}
```

**Config shapes by type:**
- `:webhook` — `%{"url" => "...", "headers" => %{}, "method" => "POST"}`
- `:slack` — `%{"url" => "https://hooks.slack.com/..."}`
- `:email` — `%{"to" => ["ops@example.com"], "from" => "alerts@switchtelemetry.local"}`

### AlertChannelBinding

Links an alert rule to one or more notification channels.

```elixir
%AlertChannelBinding{
  id: "acb_...",
  alert_rule_id: "alr_...",
  notification_channel_id: "nch_...",
  inserted_at: ~U[...]
}
```

## Architecture

### Alert Evaluation Pipeline

```
┌──────────────────┐
│  AlertEvaluator   │  Oban worker, runs every 30s on collector nodes
│  (periodic scan)  │
└────────┬─────────┘
         │ For each enabled AlertRule:
         │   1. Query recent metrics (Metrics.Queries)
         │   2. Apply condition logic (pure function)
         │   3. Check duration/cooldown constraints
         │
         ▼
┌──────────────────┐
│ State transition  │  :ok → :firing, :firing → :resolved
│ (DB update)       │  Creates AlertEvent record
└────────┬─────────┘
         │ If state changed:
         │
         ▼
┌──────────────────┐
│ AlertNotifier     │  Oban worker per (event, channel) pair
│ (async dispatch)  │  Enqueued from AlertEvaluator
└────────┬─────────┘
         │
         ├──→ Webhook (Finch HTTP POST)
         ├──→ Slack  (Finch HTTP POST with formatted blocks)
         └──→ Email  (Swoosh adapter)
```

### Key Design Decisions

1. **Oban for evaluation, not GenServer** — AlertEvaluator is a periodic Oban job (uses existing `discovery` pattern). No need for a long-lived process. Oban handles scheduling, retries, and leader election (only one node evaluates at a time).

2. **Database-driven state** — Alert rule state (`:ok`/`:firing`/`:acknowledged`) lives in PostgreSQL, not process memory. Survives restarts. Multiple evaluator runs are idempotent.

3. **Separate notification workers** — Each notification is its own Oban job. If Slack is down, email still sends. Failed notifications retry independently.

4. **Pure evaluation logic** — The condition checking is a pure function in `SwitchTelemetry.Alerting.Evaluator` (no DB, no side effects). Easy to test with property-based tests.

5. **Finch for HTTP** — Add `Finch` to the supervision tree for webhook/Slack calls. Already available via Phoenix's dependency tree but we'll configure a named instance.

6. **Swoosh for email** — Standard Phoenix mailer. Add `swoosh` + adapter dep. Optional — system works without email if not configured.

### PubSub Integration

When alert state changes:
```elixir
Phoenix.PubSub.broadcast(SwitchTelemetry.PubSub, "alerts", {:alert_fired, alert_event})
Phoenix.PubSub.broadcast(SwitchTelemetry.PubSub, "alerts:#{device_id}", {:alert_fired, alert_event})
```

Dashboard LiveViews subscribe to `"alerts"` topic for real-time alert badges/banners.

### Supervision Tree Changes

```
common_children:
  + {Finch, name: SwitchTelemetry.Finch}     # HTTP client for webhooks

# Oban queues (already configured):
#   notifications: 5  ← already exists in config.exs
```

No new GenServers needed. Finch pool is the only addition to the supervision tree.

## Database Migrations

### create_alert_rules

```elixir
create table(:alert_rules, primary_key: false) do
  add :id, :string, primary_key: true
  add :name, :string, null: false
  add :description, :string
  add :device_id, references(:devices, type: :string, on_delete: :delete_all)
  add :path, :string, null: false
  add :condition, :string, null: false     # above, below, absent, rate_increase
  add :threshold, :float
  add :duration_seconds, :integer, null: false, default: 60
  add :cooldown_seconds, :integer, null: false, default: 300
  add :severity, :string, null: false, default: "warning"
  add :enabled, :boolean, null: false, default: true
  add :state, :string, null: false, default: "ok"
  add :last_fired_at, :utc_datetime_usec
  add :last_resolved_at, :utc_datetime_usec
  timestamps(type: :utc_datetime_usec)
end

create index(:alert_rules, [:device_id])
create index(:alert_rules, [:enabled, :state])
create unique_index(:alert_rules, [:name])
```

### create_alert_events

```elixir
create table(:alert_events, primary_key: false) do
  add :id, :string, primary_key: true
  add :alert_rule_id, references(:alert_rules, type: :string, on_delete: :delete_all), null: false
  add :device_id, :string
  add :status, :string, null: false
  add :value, :float
  add :message, :string
  add :metadata, :map, default: %{}
  add :inserted_at, :utc_datetime_usec, null: false
end

create index(:alert_events, [:alert_rule_id])
create index(:alert_events, [:device_id, :inserted_at])
create index(:alert_events, [:inserted_at])
```

### create_notification_channels

```elixir
create table(:notification_channels, primary_key: false) do
  add :id, :string, primary_key: true
  add :name, :string, null: false
  add :type, :string, null: false          # webhook, slack, email
  add :config, :map, null: false, default: %{}
  add :enabled, :boolean, null: false, default: true
  timestamps(type: :utc_datetime_usec)
end

create unique_index(:notification_channels, [:name])
```

### create_alert_channel_bindings

```elixir
create table(:alert_channel_bindings, primary_key: false) do
  add :id, :string, primary_key: true
  add :alert_rule_id, references(:alert_rules, type: :string, on_delete: :delete_all), null: false
  add :notification_channel_id, references(:notification_channels, type: :string, on_delete: :delete_all), null: false
  add :inserted_at, :utc_datetime_usec, null: false
end

create unique_index(:alert_channel_bindings, [:alert_rule_id, :notification_channel_id])
```

## Module Structure

```
lib/switch_telemetry/
  alerting/
    alert_rule.ex              # Ecto schema
    alert_event.ex             # Ecto schema
    notification_channel.ex    # Ecto schema
    alert_channel_binding.ex   # Ecto schema
    evaluator.ex               # Pure functions: check conditions, compare thresholds
    notifier.ex                # Dispatches to webhook/slack/email
  alerting.ex                  # Context module: CRUD, query helpers

  workers/
    alert_evaluator.ex         # Oban worker: periodic rule evaluation
    alert_notifier.ex          # Oban worker: send one notification

lib/switch_telemetry_web/
  live/
    alert_live/
      index.ex                 # List alert rules, active alerts, event history
      rule_form.ex             # Create/edit alert rule form (LiveComponent)
      channel_form.ex          # Create/edit notification channel form (LiveComponent)
```

## LiveView Pages

### /alerts — Alert Dashboard

- **Active Alerts** panel: currently firing alerts with severity badges, device info, duration
- **Alert Rules** table: name, condition, severity, state, enabled toggle, edit/delete actions
- **Recent Events** feed: last 50 alert events with status, timestamps, values
- Create/edit rule via modal form (LiveComponent)

### /alerts/channels — Notification Channels

- List channels: name, type, enabled toggle
- Create/edit channel via modal form
- Test button: sends a test notification through the channel

### Real-time on existing dashboards

- Alert badge in app layout header showing count of firing alerts
- Per-device alert indicator on DeviceLive.Show

## Router Changes

```elixir
scope "/", SwitchTelemetryWeb do
  pipe_through :browser

  # ... existing routes ...

  live "/alerts", AlertLive.Index, :index
  live "/alerts/rules/new", AlertLive.Index, :new_rule
  live "/alerts/rules/:id/edit", AlertLive.Index, :edit_rule
  live "/alerts/channels", AlertLive.Index, :channels
  live "/alerts/channels/new", AlertLive.Index, :new_channel
  live "/alerts/channels/:id/edit", AlertLive.Index, :edit_channel
end
```

## Dependencies

```elixir
# New deps in mix.exs
{:finch, "~> 0.18"},         # HTTP client for webhooks/Slack
{:swoosh, "~> 1.16"},        # Email sending
```

## Configuration

```elixir
# config/config.exs
config :switch_telemetry, SwitchTelemetry.Alerting,
  evaluation_interval_seconds: 30,
  max_events_per_rule: 1000    # auto-prune old events

# config/runtime.exs (production)
config :switch_telemetry, SwitchTelemetry.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("SMTP_RELAY"),
  port: System.get_env("SMTP_PORT", "587") |> String.to_integer(),
  username: System.get_env("SMTP_USERNAME"),
  password: System.get_env("SMTP_PASSWORD")
```

## Testing Strategy

- **Evaluator pure functions**: Unit tests for each condition type (above/below/absent/rate_increase) with edge cases. Property-based tests with StreamData for threshold boundaries.
- **AlertEvaluator worker**: Integration test with seeded metrics + alert rules, verify state transitions and event creation.
- **AlertNotifier worker**: Mock HTTP calls with Mox (define `SwitchTelemetry.HTTPClientBehaviour`). Verify payload format for webhook/Slack.
- **LiveView**: Test alert list rendering, rule creation form, channel management.
- **PubSub**: Test that firing an alert broadcasts to subscribers.
