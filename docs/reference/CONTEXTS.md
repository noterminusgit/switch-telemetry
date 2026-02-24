# Domain Contexts, Schemas & Authorization Reference

## Contexts

### Accounts (`SwitchTelemetry.Accounts`)
Registration, login, session tokens, password reset, email confirmation, magic links, role management, admin email allowlist.

Key functions: `register_user/1`, `get_user_by_email_and_password/2`, `generate_user_session_token/1`, `get_user_by_session_token/1`, `update_user_role/2`, `deliver_magic_link_instructions/2`, `verify_magic_link_token/1`, `get_or_create_user_for_magic_link/1`, `list_users/0`, `list_admin_emails/0`, `admin_email?/1`, `maybe_promote_to_admin/1`.

### Devices (`SwitchTelemetry.Devices`)
Device and credential CRUD, collector assignment.

Key functions: `list_devices/0`, `list_devices_by_status/1`, `create_device/1`, `update_device/2`, `list_devices_for_collector/1`, `get_device_with_credential!/1`, `get_device_with_subscriptions!/1`, `default_gnmi_encoding/1`, `list_credentials/0`, `list_credentials_for_select/0`, `create_credential/1`.

### Collector (`SwitchTelemetry.Collector`)
Subscription CRUD and control.

Key functions: `list_subscriptions/0`, `list_subscriptions_for_device/1`, `create_subscription/1`, `update_subscription/2`, `toggle_subscription/1`.

### Metrics (`SwitchTelemetry.Metrics`)
Thin facade delegating to configured backend.

Key functions: `insert_batch/1`, `get_latest/2`, `get_time_series/4`.

### Dashboards (`SwitchTelemetry.Dashboards`)
Dashboard and widget CRUD, cloning, device/path pickers.

Key functions: `list_dashboards/0`, `create_dashboard/1`, `add_widget/2`, `update_widget/2`, `clone_dashboard/2`, `list_device_options/0`, `list_devices_for_widget_picker/0`, `list_paths_for_device/1`.

### Alerting (`SwitchTelemetry.Alerting`)
Alert rules, notification channels, events, and channel bindings.

Key functions: `list_alert_rules/0`, `list_enabled_rules/0`, `create_alert_rule/1`, `bind_channel/2`, `unbind_channel/2`, `list_channels_for_rule/1`, `create_event/1`, `list_events/2`, `list_recent_events/1`, `update_rule_state/3`.

### Settings (`SwitchTelemetry.Settings`)
SMTP and security settings (single-row pattern — get-or-create on first access).

Key functions: `get_smtp_settings/0`, `update_smtp_settings/1`, `get_security_settings/0`, `update_security_settings/1`.

## Schemas

| Schema | Table | Key Fields |
|--------|-------|------------|
| `Devices.Device` | `devices` | hostname (unique), ip_address (unique), platform (enum), transport (enum), gnmi_port, netconf_port, secure_mode, gnmi_encoding, status, assigned_collector, tags, collection_interval_ms |
| `Devices.Credential` | `credentials` | name (unique), username, password*, ssh_key*, tls_cert*, tls_key*, ca_cert* |
| `Collector.Subscription` | `subscriptions` | device_id, paths (string[]), mode (stream/poll/once), sample_interval_ns, encoding, enabled |
| `Dashboards.Dashboard` | `dashboards` | name (unique), description, layout, refresh_interval_ms, is_public, tags, created_by |
| `Dashboards.Widget` | `widgets` | dashboard_id, title, chart_type (line/bar/area/points/gauge/table), position (map), time_range (map), queries (map[]) |
| `Alerting.AlertRule` | `alert_rules` | device_id, name (unique), path, condition (above/below/absent/rate_increase), threshold, duration_seconds, cooldown_seconds, severity, enabled, state (ok/firing/acknowledged), created_by |
| `Alerting.AlertEvent` | `alert_events` | alert_rule_id, device_id, status (firing/resolved/acknowledged), value, message, metadata |
| `Alerting.NotificationChannel` | `notification_channels` | name (unique), type (webhook/slack/email), config (map), enabled |
| `Alerting.AlertChannelBinding` | `alert_channel_bindings` | alert_rule_id, notification_channel_id (unique composite) |
| `Accounts.User` | `users` | email (unique), hashed_password, role (admin/operator/viewer), confirmed_at |
| `Accounts.UserToken` | `user_tokens` | token, context (session/reset_password/etc), sent_to, user_id |
| `Accounts.AdminEmail` | `admin_emails` | email (unique) — admin allowlist |
| `Settings.SecuritySetting` | `security_settings` | require_secure_gnmi, require_credentials |
| `Settings.SmtpSetting` | `smtp_settings` | relay, port, username, password*, from_email, from_name, tls, enabled |

\* = encrypted with Cloak (AES-256-GCM via `SwitchTelemetry.Encrypted.Binary`)

**Platform enums**: cisco_iosxr, cisco_iosxe, cisco_nxos, juniper_junos, arista_eos, nokia_sros

**Relationships**: Device belongs_to Credential, has_many Subscriptions. Dashboard has_many Widgets, belongs_to User (created_by). AlertRule belongs_to Device and User, has_many AlertEvents and AlertChannelBindings. NotificationChannel has_many AlertChannelBindings.

## Authorization

`Authorization.can?(user, action, resource)` — pattern-matched predicate:

**Admin** (`:admin`): All actions on all resources.

**Operator** (`:operator`):
- View everything
- Create/edit devices and alert rules
- Create dashboards; edit/delete own dashboards (owner match on `created_by`)

**Viewer** (`:viewer`):
- View devices, alerts, dashboard list
- View public dashboards and own dashboards

**Default**: deny.

**Plugs** (in `user_auth.ex`): `fetch_current_user`, `require_authenticated_user`, `require_admin`.

**LiveView on_mount hooks**: `:mount_current_user`, `:ensure_authenticated`, `:ensure_admin`.

## Behaviours

### Metrics.Backend
5 callbacks: `insert_batch/1`, `get_latest/2`, `query/3`, `query_raw/4`, `query_rate/4`. Plus `query_by_prefix/3` on InfluxBackend. Active backend configured via `:metrics_backend` app env.

### Collector.GrpcClient
7 callbacks: `connect/2`, `disconnect/1`, `subscribe/1`, `send_request/2`, `recv/1`, `capabilities/2`, `capabilities/3`. Default: `DefaultGrpcClient` (wraps `GRPC.Stub`).

### Collector.SshClient
5 callbacks: `connect/3`, `session_channel/2`, `subsystem/4`, `send/3`, `close/1`. Default: `DefaultSshClient` (wraps Erlang `:ssh`).

### Dispatch Pattern
```elixir
Application.get_env(:switch_telemetry, :grpc_client, DefaultGrpcClient)
```
Test config overrides with Mox mocks in `test/support/mocks.ex`:
- `SwitchTelemetry.Metrics.MockBackend`
- `SwitchTelemetry.Collector.MockGrpcClient`
- `SwitchTelemetry.Collector.MockSshClient`
