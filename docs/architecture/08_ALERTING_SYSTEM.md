# 08: Alerting System

## Overview

The alerting system evaluates metric data against user-defined threshold rules, fires events on state transitions, and delivers notifications through configurable channels (webhook, Slack, email). It is built on four Ecto schemas, a pure evaluation engine, three Oban workers, and Phoenix PubSub for real-time UI updates.

The pipeline runs every minute:

```
Oban Cron (every 1m)
       |
       v
 AlertEvaluator worker
       |
       |  for each enabled rule:
       |    1. Fetch recent metrics from InfluxDB
       |    2. Evaluate rule via Evaluator (pure functions)
       |    3. Persist state transition + AlertEvent
       |    4. Enqueue AlertNotifier jobs for bound channels
       |    5. Broadcast {:alert_event, event} via PubSub
       |
       v
 AlertNotifier worker (queue: notifications, up to 5 retries)
       |
       |  for each bound channel:
       |    - webhook: JSON POST via Finch
       |    - slack:   Block Kit POST via Finch
       |    - email:   Swoosh delivery via Mailer
       |
       v
 AlertEventPruner worker (daily at 03:00 UTC)
       |
       |  Delete events older than 30 days,
       |  keeping at least 100 per rule
```

## Schemas

### AlertRule (`alert_rules`)

Defined in `lib/switch_telemetry/alerting/alert_rule.ex`.

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `:string` (UUID) | -- | Primary key, auto-generated |
| `name` | `:string` | -- | Unique human-readable name (max 255 chars) |
| `description` | `:string` | `nil` | Optional description (max 1000 chars) |
| `path` | `:string` | -- | Metric path to evaluate (max 512 chars) |
| `condition` | `Ecto.Enum` | -- | One of `:above`, `:below`, `:absent`, `:rate_increase` |
| `threshold` | `:float` | `nil` | Numeric threshold (required unless condition is `:absent`) |
| `duration_seconds` | `:integer` | `60` | How far back to look when querying metrics |
| `cooldown_seconds` | `:integer` | `300` | Minimum seconds between repeated firings |
| `severity` | `Ecto.Enum` | `:warning` | One of `:info`, `:warning`, `:critical` |
| `enabled` | `:boolean` | `true` | Whether the rule is evaluated |
| `state` | `Ecto.Enum` | `:ok` | One of `:ok`, `:firing`, `:acknowledged` |
| `last_fired_at` | `:utc_datetime_usec` | `nil` | Timestamp of last firing transition |
| `last_resolved_at` | `:utc_datetime_usec` | `nil` | Timestamp of last resolution |
| `device_id` | `:string` (FK) | `nil` | Optional association to a specific `Device` |
| `created_by` | `:string` (FK) | `nil` | Optional association to the creating `User` |

**Associations:**

- `belongs_to :device` -- optional scoping to a single device
- `belongs_to :creator` (via `created_by` foreign key) -- the user who created the rule
- `has_many :events` -- all `AlertEvent` records for this rule
- `has_many :channel_bindings` -- junction records linking to `NotificationChannel`

**Validations:**

- `name`, `path`, and `condition` are required
- `threshold` is required unless `condition` is `:absent`
- `duration_seconds` must be greater than 0
- `cooldown_seconds` must be greater than or equal to 0
- `name` has a unique constraint

### AlertEvent (`alert_events`)

Defined in `lib/switch_telemetry/alerting/alert_event.ex`.

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `:string` (UUID) | -- | Primary key |
| `alert_rule_id` | `:string` (FK) | -- | The rule that produced this event |
| `device_id` | `:string` | `nil` | Device involved (copied from the rule) |
| `status` | `Ecto.Enum` | -- | One of `:firing`, `:resolved`, `:acknowledged` |
| `value` | `:float` | `nil` | The metric value that triggered the event |
| `message` | `:string` | `nil` | Human-readable alert message |
| `metadata` | `:map` | `%{}` | Arbitrary metadata (threshold, condition, etc.) |
| `inserted_at` | `:utc_datetime_usec` | `DateTime.utc_now()` | When the event occurred |

**Associations:**

- `belongs_to :alert_rule`

### NotificationChannel (`notification_channels`)

Defined in `lib/switch_telemetry/alerting/notification_channel.ex`.

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `:string` (UUID) | -- | Primary key |
| `name` | `:string` | -- | Unique human-readable name (max 255 chars) |
| `type` | `Ecto.Enum` | -- | One of `:webhook`, `:slack`, `:email` |
| `config` | `:map` | `%{}` | Channel-specific configuration (URL, recipients, etc.) |
| `enabled` | `:boolean` | `true` | Whether the channel is active |

**Config map examples by type:**

- Webhook: `%{"url" => "https://example.com/hook"}`
- Slack: `%{"url" => "https://hooks.slack.com/services/..."}`
- Email: `%{"to" => ["ops@example.com"], "from" => {"Alerts", "alerts@example.com"}}`

### AlertChannelBinding (`alert_channel_bindings`)

Defined in `lib/switch_telemetry/alerting/alert_channel_binding.ex`.

Junction table linking alert rules to notification channels (many-to-many).

| Field | Type | Description |
|---|---|---|
| `id` | `:string` (UUID) | Primary key |
| `alert_rule_id` | `:string` (FK) | References `alert_rules` |
| `notification_channel_id` | `:string` (FK) | References `notification_channels` |
| `inserted_at` | `:utc_datetime_usec` | When the binding was created |

Has a unique constraint on `(alert_rule_id, notification_channel_id)` to prevent duplicate bindings.

## State Machine

Alert rules transition between three states:

```
                  condition met
                  + cooldown elapsed
         ┌────────────────────────────┐
         │                            │
         v                            │
       ┌──────┐   condition met    ┌──────────┐
       │  ok  │ ─────────────────> │ firing   │
       └──────┘                    └──────────┘
         ^                            │
         │                            │ user action
         │   condition no longer      v
         │   met (auto-resolve)   ┌──────────────┐
         │ <───────────────────── │ acknowledged │
         │                        └──────────────┘
         │                            │
         └────────────────────────────┘
                condition no longer met
```

**State transitions:**

| From | To | Trigger | Side Effects |
|---|---|---|---|
| `:ok` | `:firing` | Condition met and cooldown elapsed | Sets `last_fired_at`, creates firing event, enqueues notifications, broadcasts |
| `:firing` | `:ok` | Condition no longer met | Sets `last_resolved_at`, creates resolved event, enqueues notifications, broadcasts |
| `:firing` | `:acknowledged` | User clicks "Acknowledge" in UI | Updates state only (via `update_rule_state/2`) |
| `:firing` | `:firing` | Condition still met | No action (suppressed -- already firing) |

**Cooldown enforcement:**

When a rule transitions to `:firing`, the `last_fired_at` timestamp is recorded. On subsequent evaluations, the rule will not fire again until `cooldown_seconds` has elapsed since `last_fired_at`. This prevents alert storms from generating excessive events and notifications. The cooldown check is performed by `Evaluator.should_fire?/2`:

```elixir
@spec should_fire?(map(), DateTime.t()) :: boolean()
def should_fire?(%{last_fired_at: nil}, _current_time), do: true

def should_fire?(
      %{last_fired_at: last_fired_at, cooldown_seconds: cooldown_seconds},
      current_time
    ) do
  DateTime.diff(current_time, last_fired_at, :second) >= cooldown_seconds
end
```

## Evaluator

The `SwitchTelemetry.Alerting.Evaluator` module (`lib/switch_telemetry/alerting/evaluator.ex`) contains pure functions with no database access or side effects. It is the core decision engine for the alerting pipeline.

### `evaluate_rule/2`

Orchestrates the full evaluation of a rule against a set of metrics. Handles value extraction, condition checking, cooldown enforcement, and state transition decisions.

```elixir
@spec evaluate_rule(map(), [map()]) ::
        {:firing, number() | nil, String.t()} | {:resolved, String.t()} | :ok
def evaluate_rule(rule, metrics)
```

Returns:

- `{:firing, value, message}` -- the rule should transition from `:ok` to `:firing`
- `{:resolved, message}` -- the rule should transition from `:firing` to `:ok`
- `:ok` -- no state change needed (already firing, within cooldown, or condition not met)

Logic flow:

1. Extract the relevant metric value (latest `value_float` for most conditions, or calculated rate for `:rate_increase`)
2. Call `check_condition/3` to test the condition against the threshold
3. If the condition is met:
   - If already `:firing`, return `:ok` (suppress duplicate)
   - If within cooldown, return `:ok`
   - Otherwise, return `{:firing, value, message}`
4. If the condition is not met:
   - If currently `:firing`, return `{:resolved, message}`
   - Otherwise, return `:ok`

### `check_condition/3`

Tests a single metric value against a condition and threshold.

```elixir
@spec check_condition(atom(), number() | nil, number() | nil) ::
        {:firing, number() | nil} | :ok
```

| Condition | Fires When | `nil` Value |
|---|---|---|
| `:above` | `value > threshold` | Returns `:ok` |
| `:below` | `value < threshold` | Returns `:ok` |
| `:absent` | Value is `nil` | Returns `{:firing, nil}` |
| `:rate_increase` | `rate > threshold` | Returns `:ok` |

### `extract_value/1`

Extracts the latest `value_float` from a list of metric maps ordered descending by time.

```elixir
@spec extract_value([map()]) :: number() | nil
def extract_value([]), do: nil
def extract_value([latest | _rest]), do: latest.value_float
```

### `calculate_rate/2`

Calculates the rate of change (per second) across a list of metric maps. Expects metrics ordered descending by time (newest first).

```elixir
@spec calculate_rate([map()], integer()) :: float() | nil
def calculate_rate(metrics, _duration_seconds) when length(metrics) < 2, do: nil

def calculate_rate(metrics, _duration_seconds) do
  newest = List.first(metrics)
  oldest = List.last(metrics)
  elapsed = DateTime.diff(newest.time, oldest.time, :second)

  if elapsed == 0, do: nil, else: (newest.value_float - oldest.value_float) / elapsed
end
```

Returns `nil` if fewer than 2 data points or if elapsed time is zero.

### `build_message/2`

Generates a human-readable alert message for a given rule and metric value. Each condition type produces a distinct message format:

```elixir
@spec build_message(map(), number() | nil) :: String.t()
```

Examples:

- `:above` -- `"High CPU: value 95.2 exceeds threshold 90.0 on path /interfaces/cpu/utilization"`
- `:below` -- `"Low Memory: value 5.1 below threshold 10.0 on path /system/memory/free"`
- `:absent` -- `"Link Down: no data received on path /interfaces/eth0/state"`
- `:rate_increase` -- `"Error Spike: rate of change 150.0/s exceeds threshold 100.0/s on path /interfaces/errors"`

## Workers

### AlertEvaluator

**Module:** `SwitchTelemetry.Workers.AlertEvaluator`

| Setting | Value |
|---|---|
| Queue | `:alerts` |
| Max attempts | `1` |
| Cron schedule | `* * * * *` (every minute) |

Runs every minute via the Oban Cron plugin. For each enabled rule:

1. Fetches recent metrics from InfluxDB via `Metrics.get_latest/2`, filtered by `rule.path`. The lookback window is derived from `rule.duration_seconds` (converted to minutes, minimum 1).
2. Calls `Evaluator.evaluate_rule/2` to determine the state transition.
3. On `:firing`:
   - Updates the rule state to `:firing` with `last_fired_at` timestamp
   - Creates an `AlertEvent` with status `:firing`, the triggering value, a human-readable message, and metadata containing the threshold and condition
   - Enqueues one `AlertNotifier` job per bound notification channel
   - Broadcasts `{:alert_event, event}` on PubSub
4. On `:resolved`:
   - Updates the rule state to `:ok` with `last_resolved_at` timestamp
   - Creates an `AlertEvent` with status `:resolved`
   - Enqueues notification jobs and broadcasts similarly
5. On `:ok`: No action.

**Note:** Rules without a `device_id` are currently skipped (device-specific rules only).

### AlertNotifier

**Module:** `SwitchTelemetry.Workers.AlertNotifier`

| Setting | Value |
|---|---|
| Queue | `:notifications` |
| Max attempts | `5` |

Delivers a single notification for one alert event through one channel. Each job carries `alert_event_id` and `channel_id` in its args.

**Delivery by channel type:**

| Type | Method | Details |
|---|---|---|
| `:webhook` | `Finch.request/2` | JSON POST to `channel.config["url"]` with `Notifier.format_webhook_payload/2` |
| `:slack` | `Finch.request/2` | JSON POST to `channel.config["url"]` with `Notifier.format_slack_payload/2` (Block Kit) |
| `:email` | `SwitchTelemetry.Mailer.deliver/1` | Swoosh email built by `Notifier.format_email/3` |

HTTP responses in the 200-299 range are considered successful. Any other status or connection error returns `{:error, reason}`, which triggers Oban's retry mechanism (up to 5 attempts).

### AlertEventPruner

**Module:** `SwitchTelemetry.Workers.AlertEventPruner`

| Setting | Value |
|---|---|
| Queue | `:maintenance` |
| Max attempts | `1` |
| Cron schedule | `0 3 * * *` (daily at 03:00 UTC) |

Prunes old alert events to prevent unbounded table growth.

**Retention policy:**

- Default max age: 30 days (configurable via `:alert_event_max_age_days` app env)
- Minimum kept per rule: 100 events (configurable via `:alert_event_min_keep_per_rule` app env)

**Algorithm:** Uses a window function (`row_number() OVER (PARTITION BY alert_rule_id ORDER BY inserted_at DESC)`) to identify the most recent 100 events per rule, then deletes all events older than the cutoff that are not in that protected set. This ensures every rule retains at least 100 events for historical context even if they are older than 30 days.

Returns `{:ok, %{deleted: count}}` with the number of pruned rows.

## Notification Delivery

The `SwitchTelemetry.Alerting.Notifier` module (`lib/switch_telemetry/alerting/notifier.ex`) formats payloads for each channel type. It contains no delivery logic -- that lives in the `AlertNotifier` worker.

### Webhook Payload

```elixir
@spec format_webhook_payload(map(), map()) :: map()
def format_webhook_payload(event, rule)
```

Produces a flat JSON object:

```json
{
  "alert_rule": "High CPU",
  "severity": "critical",
  "status": "firing",
  "device_id": "abc-123",
  "path": "/interfaces/cpu/utilization",
  "value": 95.2,
  "message": "High CPU: value 95.2 exceeds threshold 90.0 on path /interfaces/cpu/utilization",
  "fired_at": "2026-02-15T10:30:00.000000Z"
}
```

### Slack Payload (Block Kit)

```elixir
@spec format_slack_payload(map(), map()) :: map()
def format_slack_payload(event, rule)
```

Produces a Slack Block Kit structure with:

- **Header block:** Severity emoji (`:red_circle:` for critical, `:large_orange_circle:` for warning, `:large_blue_circle:` for info) followed by rule name
- **Section block with fields:** Severity, Status, Device, Path
- **Section block:** The full alert message text

### Email

```elixir
@spec format_email(map(), map(), map()) :: Swoosh.Email.t()
def format_email(event, rule, channel_config)
```

Builds a `Swoosh.Email` struct:

- **To:** `channel_config["to"]` (list of recipients)
- **From:** `channel_config["from"]` or default `{"Switch Telemetry", "alerts@switchtelemetry.local"}`
- **Subject:** `[SEVERITY] Rule Name` (e.g., `[CRITICAL] High CPU`)
- **Body:** Plain text, the event message

## Context Module

The `SwitchTelemetry.Alerting` context (`lib/switch_telemetry/alerting.ex`) provides CRUD operations and state management for all alerting schemas. Key functions:

### AlertRule Operations

| Function | Spec | Description |
|---|---|---|
| `list_alert_rules/0` | `:: [AlertRule.t()]` | All rules |
| `list_enabled_rules/0` | `:: [AlertRule.t()]` | Rules where `enabled == true` |
| `get_alert_rule!/1` | `:: AlertRule.t()` | Fetch by ID or raise |
| `get_alert_rule/1` | `:: AlertRule.t() \| nil` | Fetch by ID |
| `create_alert_rule/1` | `:: {:ok, AlertRule.t()} \| {:error, Changeset.t()}` | Create with auto-generated ID |
| `update_alert_rule/2` | `:: {:ok, AlertRule.t()} \| {:error, Changeset.t()}` | Update fields |
| `delete_alert_rule/1` | `:: {:ok, AlertRule.t()} \| {:error, Changeset.t()}` | Delete |

### NotificationChannel Operations

| Function | Spec | Description |
|---|---|---|
| `list_channels/0` | `:: [NotificationChannel.t()]` | All channels |
| `get_channel!/1` | `:: NotificationChannel.t()` | Fetch by ID or raise |
| `create_channel/1` | `:: {:ok, NotificationChannel.t()} \| {:error, Changeset.t()}` | Create with auto-generated ID |
| `update_channel/2` | `:: {:ok, NotificationChannel.t()} \| {:error, Changeset.t()}` | Update fields |
| `delete_channel/1` | `:: {:ok, NotificationChannel.t()} \| {:error, Changeset.t()}` | Delete |

### Binding Operations

| Function | Spec | Description |
|---|---|---|
| `bind_channel/2` | `:: {:ok, AlertChannelBinding.t()} \| {:error, Changeset.t()}` | Link a rule to a channel |
| `unbind_channel/2` | `:: {:ok, AlertChannelBinding.t()} \| {:error, :not_found} \| {:error, Changeset.t()}` | Remove a rule-channel link |
| `list_channels_for_rule/1` | `:: [NotificationChannel.t()]` | All channels bound to a rule |

### Event Operations

| Function | Spec | Description |
|---|---|---|
| `create_event/1` | `:: {:ok, AlertEvent.t()} \| {:error, Changeset.t()}` | Create with auto-generated ID and timestamp |
| `list_events/2` | `:: [AlertEvent.t()]` | Events for a rule, newest first (default limit: 50) |
| `list_recent_events/1` | `:: [AlertEvent.t()]` | All recent events across rules (default limit: 50) |

### State Management

```elixir
@spec update_rule_state(AlertRule.t(), atom(), keyword()) ::
        {:ok, AlertRule.t()} | {:error, Ecto.Changeset.t()}
def update_rule_state(rule, new_state, opts \\ [])
```

Updates a rule's state and associated timestamps:

- Transitioning to `:firing` sets `last_fired_at`
- Transitioning to `:ok` sets `last_resolved_at`
- Transitioning to `:acknowledged` updates state only

Accepts an optional `:timestamp` keyword (defaults to `DateTime.utc_now()`).

## PubSub Integration

The `AlertEvaluator` worker broadcasts events on two PubSub topics after every state transition:

| Topic | Published When | Message Format |
|---|---|---|
| `"alerts"` | Every firing or resolved event | `{:alert_event, %AlertEvent{}}` |
| `"alerts:#{device_id}"` | Only when the event has a non-nil `device_id` | `{:alert_event, %AlertEvent{}}` |

Broadcasting code from the worker:

```elixir
defp broadcast_alert(event) do
  topic = "alerts"
  Phoenix.PubSub.broadcast(SwitchTelemetry.PubSub, topic, {:alert_event, event})

  if event.device_id do
    Phoenix.PubSub.broadcast(
      SwitchTelemetry.PubSub,
      "alerts:#{event.device_id}",
      {:alert_event, event}
    )
  end
end
```

This allows web nodes to receive alert events in real time without polling the database.

## LiveView Integration

`SwitchTelemetryWeb.AlertLive.Index` (`lib/switch_telemetry_web/live/alert_live/index.ex`) provides the alerts management UI.

### Mount and Subscription

On mount (when connected), the LiveView subscribes to the `"alerts"` PubSub topic and loads initial data:

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(SwitchTelemetry.PubSub, "alerts")
  end

  rules = Alerting.list_alert_rules()
  events = Alerting.list_recent_events(limit: 20)
  channels = Alerting.list_channels()
  firing_rules = Enum.filter(rules, &(&1.state == :firing))

  {:ok, assign(socket, rules: rules, events: events, channels: channels, firing_rules: firing_rules, page_title: "Alerts")}
end
```

### Real-Time Updates

When a `{:alert_event, _event}` message arrives via PubSub, the LiveView refreshes all rules, events, and firing rules from the database:

```elixir
def handle_info({:alert_event, _event}, socket) do
  rules = Alerting.list_alert_rules()
  events = Alerting.list_recent_events(limit: 20)
  firing_rules = Enum.filter(rules, &(&1.state == :firing))
  {:noreply, assign(socket, rules: rules, events: events, firing_rules: firing_rules)}
end
```

### UI Panels

The view renders three panels:

1. **Active Alerts** -- displays all rules in `:firing` state with severity badge, rule name, path/condition details, and an "Acknowledge" button
2. **Alert Rules** -- table of all rules showing name, path, condition/threshold, severity, state, enabled toggle, and edit/delete actions
3. **Recent Events** -- chronological list of the 20 most recent events with status indicator dot, timestamp, status, value, and message

### Supported Actions

| Live Action | Route Pattern | Description |
|---|---|---|
| `:index` | `/alerts` | Main alerts view |
| `:new_rule` | `/alerts/rules/new` | Create alert rule form |
| `:edit_rule` | `/alerts/rules/:id/edit` | Edit alert rule form |
| `:channels` | `/alerts/channels` | Channel management view |
| `:new_channel` | `/alerts/channels/new` | Create channel form |
| `:edit_channel` | `/alerts/channels/:id/edit` | Edit channel form |

### User Events

| Event | Action |
|---|---|
| `"toggle_enabled"` | Toggles a rule's `enabled` flag |
| `"delete_rule"` | Deletes a rule and refreshes the list |
| `"acknowledge"` | Transitions a firing rule to `:acknowledged` state |
| `"delete_channel"` | Deletes a notification channel |

## Oban Configuration

From `config/config.exs`:

```elixir
config :switch_telemetry, Oban,
  queues: [default: 10, discovery: 2, maintenance: 1, notifications: 5, alerts: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", SwitchTelemetry.Workers.AlertEvaluator},
       {"0 3 * * *", SwitchTelemetry.Workers.AlertEventPruner}
     ]}
  ]
```

- The `alerts` queue has concurrency 1 to ensure sequential evaluation (prevents race conditions on rule state)
- The `notifications` queue has concurrency 5 to allow parallel delivery across multiple channels
- The `maintenance` queue has concurrency 1 for the daily pruner
