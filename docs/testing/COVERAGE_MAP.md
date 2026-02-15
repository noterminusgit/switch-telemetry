# Test Coverage Map

Module-to-test-file mapping for Switch Telemetry. Updated 2026-02-15.

## Legend

**Type**: schema, context, genserver, worker, liveview, controller, component, behaviour, plug, utility
**Status**: covered (dedicated test), partial (tested indirectly), untested

## Accounts

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Accounts` | `test/switch_telemetry/accounts_test.exs` | context | covered |
| `SwitchTelemetry.Accounts.User` | via accounts_test | schema | partial |
| `SwitchTelemetry.Accounts.UserToken` | via accounts_test | schema | partial |
| `SwitchTelemetry.Accounts.AdminEmail` | `test/switch_telemetry/accounts/admin_email_test.exs` | schema | covered |
| `SwitchTelemetry.Accounts.UserNotifier` | `test/switch_telemetry/accounts/user_notifier_test.exs` | utility | covered |
| `SwitchTelemetry.Authorization` | `test/switch_telemetry/authorization_test.exs` | utility | covered |
| `SwitchTelemetry.Authorization` (property) | `test/switch_telemetry/authorization_property_test.exs` | utility | covered |

## Devices

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Devices` | `test/switch_telemetry/devices_test.exs` | context | covered |
| `SwitchTelemetry.Devices.Device` | `test/switch_telemetry/devices/device_test.exs` | schema | covered |
| `SwitchTelemetry.Devices.Credential` | `test/switch_telemetry/devices/credential_test.exs` | schema | covered |

## Metrics

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Metrics` | `test/switch_telemetry/metrics_test.exs` | context | covered |
| `SwitchTelemetry.Metrics.Backend` | via influx_backend_test | behaviour | partial |
| `SwitchTelemetry.Metrics.InfluxBackend` | `test/switch_telemetry/metrics/influx_backend_test.exs` | utility | covered |
| `SwitchTelemetry.Metrics.QueryRouter` | `test/switch_telemetry/metrics/query_router_test.exs` | utility | covered |
| `SwitchTelemetry.InfluxDB` | via influx_backend_test | utility | partial |

## Dashboards

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Dashboards` | `test/switch_telemetry/dashboards_test.exs` | context | covered |
| `SwitchTelemetry.Dashboards` (advanced) | `test/switch_telemetry/dashboards/advanced_test.exs` | context | covered |
| `SwitchTelemetry.Dashboards.Dashboard` | `test/switch_telemetry/dashboards/dashboard_test.exs` | schema | covered |
| `SwitchTelemetry.Dashboards.Widget` | `test/switch_telemetry/dashboards/widget_test.exs` | schema | covered |

## Alerting

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Alerting` | `test/switch_telemetry/alerting_test.exs` | context | covered |
| `SwitchTelemetry.Alerting` (integration) | `test/switch_telemetry/alerting/integration_test.exs` | context | covered |
| `SwitchTelemetry.Alerting.AlertRule` | `test/switch_telemetry/alerting/alert_rule_test.exs` | schema | covered |
| `SwitchTelemetry.Alerting.AlertEvent` | via alerting_test | schema | partial |
| `SwitchTelemetry.Alerting.NotificationChannel` | `test/switch_telemetry/alerting/notification_channel_test.exs` | schema | covered |
| `SwitchTelemetry.Alerting.AlertChannelBinding` | via alerting_test | schema | partial |
| `SwitchTelemetry.Alerting.Evaluator` | `test/switch_telemetry/alerting/evaluator_test.exs` | utility | covered |
| `SwitchTelemetry.Alerting.Evaluator` (property) | `test/switch_telemetry/alerting/evaluator_property_test.exs` | utility | covered |
| `SwitchTelemetry.Alerting.Notifier` | `test/switch_telemetry/alerting/notifier_test.exs` | utility | covered |

## Collector

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Collector` | `test/switch_telemetry/collector_test.exs` | context | covered |
| `SwitchTelemetry.Collector.GnmiSession` | `test/switch_telemetry/collector/gnmi_session_test.exs` | genserver | covered |
| `SwitchTelemetry.Collector.NetconfSession` | `test/switch_telemetry/collector/netconf_session_test.exs` | genserver | covered |
| `SwitchTelemetry.Collector.DeviceManager` | `test/switch_telemetry/collector/device_manager_test.exs` | genserver | covered |
| `SwitchTelemetry.Collector.DeviceAssignment` | `test/switch_telemetry/collector/device_assignment_test.exs` | utility | covered |
| `SwitchTelemetry.Collector.NodeMonitor` | `test/switch_telemetry/collector/node_monitor_test.exs` | genserver | covered |
| `SwitchTelemetry.Collector.StreamMonitor` | `test/switch_telemetry/collector/stream_monitor_test.exs` | genserver | covered |
| `SwitchTelemetry.Collector.Subscription` | `test/switch_telemetry/collector/subscription_test.exs` | schema | covered |
| `SwitchTelemetry.Collector.Subscription` (property) | `test/switch_telemetry/collector/subscription_property_test.exs` | schema | covered |

## Workers

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Workers.AlertEvaluator` | `test/switch_telemetry/workers/alert_evaluator_test.exs` | worker | covered |
| `SwitchTelemetry.Workers.AlertNotifier` | `test/switch_telemetry/workers/alert_notifier_test.exs` | worker | covered |
| `SwitchTelemetry.Workers.AlertEventPruner` | `test/switch_telemetry/workers/alert_event_pruner_test.exs` | worker | covered |
| `SwitchTelemetry.Workers.DeviceDiscovery` | `test/switch_telemetry/workers/device_discovery_test.exs` | worker | covered |
| `SwitchTelemetry.Workers.StaleSessionCleanup` | `test/switch_telemetry/workers/stale_session_cleanup_test.exs` | worker | covered |

## Web -- LiveViews

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetryWeb.DashboardLive.Index` | `test/switch_telemetry_web/live/dashboard_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.DashboardLive.Show` | via dashboard_live_test | liveview | partial |
| `SwitchTelemetryWeb.DeviceLive.Index` | `test/switch_telemetry_web/live/device_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.DeviceLive.Show` | via device_live_test | liveview | partial |
| `SwitchTelemetryWeb.DeviceLive.Edit` | via device_live_test | liveview | partial |
| `SwitchTelemetryWeb.AlertLive.Index` | `test/switch_telemetry_web/live/alert_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.AlertLive.RuleForm` | via alert_live_test | liveview | partial |
| `SwitchTelemetryWeb.AlertLive.ChannelForm` | via alert_live_test | liveview | partial |
| `SwitchTelemetryWeb.UserLive.Index` | `test/switch_telemetry_web/live/user_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.UserLive.Settings` | via user_live_test | liveview | partial |
| `SwitchTelemetryWeb.SubscriptionLive.Index` | `test/switch_telemetry_web/live/subscription_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.SubscriptionLive.FormComponent` | via subscription_live_test | liveview | partial |
| `SwitchTelemetryWeb.CredentialLive.Index` | `test/switch_telemetry_web/live/credential_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.CredentialLive.Show` | via credential_live_test | liveview | partial |
| `SwitchTelemetryWeb.CredentialLive.Edit` | via credential_live_test | liveview | partial |
| `SwitchTelemetryWeb.AdminEmailLive.Index` | `test/switch_telemetry_web/live/admin_email_live_test.exs` | liveview | covered |
| `SwitchTelemetryWeb.StreamLive.Monitor` | `test/switch_telemetry_web/live/stream_monitor_live_test.exs` | liveview | covered |

## Web -- Controllers & Plugs

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetryWeb.UserSessionController` | `test/switch_telemetry_web/controllers/user_session_controller_test.exs` | controller | covered |
| `SwitchTelemetryWeb.PageController` | -- | controller | untested |
| `SwitchTelemetryWeb.ErrorHTML` | `test/switch_telemetry_web/controllers/error_html_test.exs` | controller | covered |
| `SwitchTelemetryWeb.ErrorJSON` | `test/switch_telemetry_web/controllers/error_json_test.exs` | controller | covered |
| `SwitchTelemetryWeb.UserAuth` | `test/switch_telemetry_web/user_auth_test.exs` | plug | covered |

## Web -- Components

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetryWeb.CoreComponents` | via LiveView tests | component | partial |
| `SwitchTelemetryWeb.TelemetryChart` | via dashboard_live_test | component | partial |
| `SwitchTelemetryWeb.TopBar` | via LiveView tests | component | partial |
| `SwitchTelemetryWeb.Sidebar` | via LiveView tests | component | partial |
| `SwitchTelemetryWeb.MobileNav` | via LiveView tests | component | partial |
| `SwitchTelemetryWeb.TimeRangePicker` | via LiveView tests | component | partial |
| `SwitchTelemetryWeb.WidgetEditor` | via LiveView tests | component | partial |
| `SwitchTelemetryWeb.Layouts` | via LiveView tests | component | partial |

## Security

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Vault` | `test/switch_telemetry/vault_test.exs` | utility | covered |
| `SwitchTelemetry.Encrypted` | via vault_test | utility | partial |
| Security: Input Validation | `test/switch_telemetry/security/input_validation_test.exs` | utility | covered |
| Security: HTTP Headers | `test/switch_telemetry_web/security/headers_test.exs` | utility | covered |

## Infrastructure (no dedicated tests)

| Module | Test File | Type | Status |
|--------|-----------|------|--------|
| `SwitchTelemetry.Application` | -- | utility | untested |
| `SwitchTelemetry.Repo` | -- | utility | untested |
| `SwitchTelemetry.Mailer` | -- | utility | untested |
| `SwitchTelemetryWeb` | -- | utility | untested |
| `SwitchTelemetryWeb.Endpoint` | -- | utility | untested |
| `SwitchTelemetryWeb.Router` | via controller/liveview tests | utility | partial |
| `SwitchTelemetryWeb.Telemetry` | -- | utility | untested |
| `SwitchTelemetryWeb.Gettext` | -- | utility | untested |
| `SwitchTelemetryWeb.UserSessionHTML` | via user_session_controller_test | component | partial |
| `SwitchTelemetry.Collector.Gnmi.Proto.*` | -- | utility | untested |

## Summary

| Status | Count |
|--------|-------|
| covered | 42 |
| partial | 24 |
| untested | 7 |
