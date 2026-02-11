# Phase 5 Implementation Plan: Alerting & Notifications

## Prerequisites
- Phases 1-4 complete (74 tests passing, zero warnings)
- TimescaleDB running with metrics hypertable

## Task Order

Tasks are grouped by dependency. Groups must be completed in order. Tasks within a group can be done in parallel where noted.

---

### Group 1: Dependencies & Schemas (foundation)

**Task 1: Add Finch and Swoosh dependencies**
- Add `{:finch, "~> 0.18"}` and `{:swoosh, "~> 1.16"}` to `mix.exs`
- Add `{:swoosh, "~> 1.16"}` to deps
- Run `mix deps.get`
- Add `{Finch, name: SwitchTelemetry.Finch}` to `common_children` in `application.ex`
- Create `lib/switch_telemetry/mailer.ex` with `use Swoosh.Mailer, otp_app: :switch_telemetry`
- Add Swoosh dev/test config to `config/config.exs` (use `Swoosh.Adapters.Local` for dev)
- Add Swoosh runtime config placeholder in `config/runtime.exs`
- Verify: `mix compile` succeeds with zero warnings

**Task 2: Create Ecto schemas** (parallel with Task 1 after deps)
- Create `lib/switch_telemetry/alerting/alert_rule.ex` — Ecto schema with changeset
  - Fields: id, name, description, device_id, path, condition (Ecto.Enum), threshold, duration_seconds, cooldown_seconds, severity (Ecto.Enum), enabled, state (Ecto.Enum), last_fired_at, last_resolved_at, timestamps
  - Validate required: name, path, condition, severity
  - Validate condition ∈ [:above, :below, :absent, :rate_increase]
  - Validate severity ∈ [:info, :warning, :critical]
  - Validate state ∈ [:ok, :firing, :acknowledged]
  - Validate threshold required when condition != :absent
  - Validate duration_seconds > 0
- Create `lib/switch_telemetry/alerting/alert_event.ex` — Ecto schema (no changeset needed, insert-only)
  - Fields: id, alert_rule_id, device_id, status (Ecto.Enum), value, message, metadata, inserted_at
- Create `lib/switch_telemetry/alerting/notification_channel.ex` — Ecto schema with changeset
  - Fields: id, name, type (Ecto.Enum), config, enabled, timestamps
  - Validate required: name, type, config
  - Validate type ∈ [:webhook, :slack, :email]
- Create `lib/switch_telemetry/alerting/alert_channel_binding.ex` — Ecto schema with changeset
  - Fields: id, alert_rule_id, notification_channel_id, inserted_at
- Tests: Schema validation tests for each schema (valid attrs, missing required fields, invalid enums)

**Task 3: Create database migrations**
- Migration `create_alert_rules` — table, indexes (device_id, enabled+state, unique name)
- Migration `create_notification_channels` — table, unique name index
- Migration `create_alert_events` — table, indexes (alert_rule_id, device_id+inserted_at, inserted_at)
- Migration `create_alert_channel_bindings` — table, unique composite index
- Run `mix ecto.migrate` and verify
- Verify: migrations apply cleanly, `mix ecto.rollback` works for each

---

### Group 2: Context & Pure Logic

**Task 4: Create Alerting context module**
- Create `lib/switch_telemetry/alerting.ex`
- CRUD for AlertRule: `list_alert_rules/0`, `list_enabled_rules/0`, `get_alert_rule!/1`, `create_alert_rule/1`, `update_alert_rule/2`, `delete_alert_rule/1`
- CRUD for NotificationChannel: `list_channels/0`, `get_channel!/1`, `create_channel/1`, `update_channel/2`, `delete_channel/1`
- AlertChannelBinding: `bind_channel/2`, `unbind_channel/2`, `list_channels_for_rule/1`
- AlertEvent: `create_event/1`, `list_events/1` (by rule_id, with limit), `list_recent_events/1` (last N across all rules)
- State management: `update_rule_state/3` (rule, new_state, opts) — updates state + timestamps atomically
- Tests: Context tests with DB (create, read, update, delete for each entity)

**Task 5: Create Evaluator pure logic module**
- Create `lib/switch_telemetry/alerting/evaluator.ex`
- `check_condition(:above, value, threshold)` → `{:firing, value}` | `:ok`
- `check_condition(:below, value, threshold)` → `{:firing, value}` | `:ok`
- `check_condition(:absent, nil, _threshold)` → `{:firing, nil}`
- `check_condition(:rate_increase, rate, threshold)` → `{:firing, rate}` | `:ok`
- `should_fire?(rule, current_time)` — checks duration and cooldown constraints
- `build_message(rule, value)` — generates human-readable alert message
- `evaluate_rule(rule, metrics)` — orchestrates: extract value, check condition, check timing → `:ok` | `{:firing, value, message}` | `{:resolved, message}`
- Tests: Comprehensive unit tests for each condition type, edge cases (nil values, exact threshold, cooldown boundary). Property tests with StreamData for threshold comparisons.

---

### Group 3: Workers

**Task 6: Create AlertEvaluator Oban worker**
- Create `lib/switch_telemetry/workers/alert_evaluator.ex`
- Queue: `:discovery` (reuse existing periodic queue, or add `:alerts` queue)
- Actually, add new `:alerts` queue with concurrency 1 to config.exs
- `perform/1`:
  1. Fetch all enabled rules via `Alerting.list_enabled_rules/0` (preload device)
  2. For each rule, query recent metrics using `Metrics.Queries.get_latest/2`
  3. Call `Evaluator.evaluate_rule/2`
  4. If state change detected: update rule state, create alert event, enqueue notification jobs
  5. Broadcast state changes via PubSub
- Schedule: self-enqueuing every 30 seconds (check Oban unique opts to prevent duplicates)
- Use `Oban.insert/1` with `unique: [period: 25]` to prevent overlapping runs
- Tests: Integration test with seeded metrics + rules, verify events created and state transitions

**Task 7: Create AlertNotifier Oban worker**
- Create `lib/switch_telemetry/workers/alert_notifier.ex`
- Queue: `:notifications` (already configured with concurrency 5)
- Args: `%{"alert_event_id" => id, "channel_id" => id}`
- `perform/1`:
  1. Load alert event (with preloaded rule) and channel
  2. Dispatch based on channel type:
     - `:webhook` → `Finch.request/3` POST JSON to configured URL
     - `:slack` → `Finch.request/3` POST Slack Block Kit formatted message
     - `:email` → `Swoosh` deliver via Mailer
  3. Return `:ok` on success, `{:error, reason}` to trigger Oban retry
- Create `lib/switch_telemetry/alerting/notifier.ex` for payload formatting:
  - `format_webhook_payload(event, rule)` → JSON map
  - `format_slack_payload(event, rule)` → Slack Block Kit structure
  - `format_email(event, rule, channel_config)` → Swoosh.Email struct
- max_attempts: 5 with exponential backoff
- Tests: Mock Finch with Mox for webhook/Slack. Mock Swoosh for email. Verify payload structure.

---

### Group 4: Scheduling

**Task 8: Wire up periodic alert evaluation**
- Add `:alerts` queue to Oban config in `config/config.exs`: `alerts: 1`
- Add `:alerts` queue to runtime.exs disabled list for web-only nodes
- Create a simple mechanism to bootstrap the recurring evaluation:
  - Option A: Use `Oban.insert/1` with unique constraint, triggered on application start
  - Option B: Use Oban cron plugin: `{Oban.Plugins.Cron, crontab: [{"*/1 * * * *", SwitchTelemetry.Workers.AlertEvaluator}]}`
  - **Use Option B** (Oban Cron) — cleaner, built-in, runs every minute. The worker itself can do sub-minute evaluation if needed.
- Add Cron plugin to Oban config
- Tests: Verify Oban config includes cron entry, worker is schedulable

---

### Group 5: LiveView UI

**Task 9: Create AlertLive.Index LiveView**
- Create `lib/switch_telemetry_web/live/alert_live/index.ex`
- Three main sections (tabs or panels):
  1. **Active Alerts**: firing alerts with severity badge, device name, duration, acknowledge button
  2. **Alert Rules**: table with name, path, condition, threshold, severity, state, enabled toggle, edit/delete
  3. **Recent Events**: reverse-chronological feed with status icon, rule name, value, timestamp
- PubSub subscription to `"alerts"` for real-time updates
- Handle `:new_rule`, `:edit_rule`, `:channels`, `:new_channel`, `:edit_channel` live_actions via modals
- Tests: LiveView tests for listing, creating rules, toggling enabled state

**Task 10: Create RuleForm LiveComponent**
- Create `lib/switch_telemetry_web/live/alert_live/rule_form.ex`
- Form fields: name, description, device (optional select), path (text input), condition (select), threshold (number), duration_seconds, cooldown_seconds, severity (select)
- Channel binding checkboxes: list all channels, check/uncheck to bind
- Validation feedback from changeset
- Tests: Test form rendering, validation errors, successful submission

**Task 11: Create ChannelForm LiveComponent**
- Create `lib/switch_telemetry_web/live/alert_live/channel_form.ex`
- Form fields: name, type (select), enabled (checkbox)
- Dynamic config fields based on type:
  - webhook: url, headers (optional)
  - slack: url
  - email: to (comma-separated), from
- "Test" button: sends test notification via the channel
- Tests: Test form rendering, type switching, config validation

**Task 12: Add routes and navigation**
- Add alert routes to `router.ex` (see design doc)
- Add "Alerts" link to app layout navigation (`app.html.heex`)
- Add alert badge to layout header showing count of firing alerts (subscribe to PubSub in root layout or app.html.heex assign)
- Add per-device alert indicator on `DeviceLive.Show` (subscribe to `"alerts:#{device_id}"`)
- Tests: Verify routes resolve, navigation links present

---

### Group 6: Polish & Integration

**Task 13: Alert event pruning worker**
- Create `lib/switch_telemetry/workers/alert_event_pruner.ex`
- Oban cron job, runs daily
- Deletes alert_events older than 30 days (configurable)
- Keeps at least the last N events per rule (configurable, default 100)
- Tests: Verify old events pruned, recent events kept

**Task 14: End-to-end integration test**
- Seed a device with metrics in DB
- Create an alert rule with threshold
- Run AlertEvaluator manually
- Assert: rule state changed to :firing, alert event created, notification job enqueued
- Run AlertNotifier with mocked HTTP
- Assert: correct payload sent
- Insert metrics below threshold
- Run AlertEvaluator again
- Assert: rule state changed to :ok, resolved event created
- Full lifecycle test

**Task 15: Documentation**
- Update CLAUDE.md with alerting module conventions
- Add alert-related entries to ALWAYS_DO.md (always use Oban for notifications, never evaluate alerts in LiveView)
- Verify zero warnings: `mix compile --warnings-as-errors`
- Verify all tests pass

---

## Estimated Scope
- 4 Ecto schemas + migrations
- 1 context module (~150 lines)
- 1 pure evaluator module (~100 lines)
- 1 notifier module (~80 lines)
- 3 Oban workers (~250 lines total)
- 3 LiveView files (~400 lines total)
- ~15 test files (~600 lines total)
- Total: ~1,600 lines of new code + tests
