# Modern Web UI Implementation Plan

## Overview

This plan documents the implementation of a modern web UI for Switch Telemetry, including sidebar navigation, enhanced device management, and stream management features.

## Implementation Status

### Phase 1: Core Components & Sidebar Layout - COMPLETE

#### New Components Created

| File | Purpose | Status |
|------|---------|--------|
| `lib/switch_telemetry_web/components/sidebar.ex` | Collapsible sidebar navigation with icons | Complete |
| `lib/switch_telemetry_web/components/top_bar.ex` | Top bar with hamburger menu and user info | Complete |
| `lib/switch_telemetry_web/components/mobile_nav.ex` | Slide-out drawer for mobile navigation | Complete |

#### Modified Files

| File | Changes | Status |
|------|---------|--------|
| `lib/switch_telemetry_web/components/core_components.ex` | Added modal, icon, dropdown, tabs, status_badge components | Complete |
| `lib/switch_telemetry_web/components/layouts/app.html.heex` | Replaced header with sidebar + top bar layout | Complete |
| `lib/switch_telemetry_web/user_auth.ex` | Added current_path tracking for nav highlighting | Complete |

#### Navigation Structure

```
Dashboards    /dashboards     (hero-chart-bar-square)
Devices       /devices        (hero-server-stack)
Streams       /streams        (hero-signal) - NEW
Alerts        /alerts         (hero-bell-alert)
Credentials   /credentials    (hero-key) - NEW
Settings      /settings       (hero-cog-6-tooth)
Admin > Users /admin/users    (hero-users, admin only)
```

### Phase 2: Device Management Enhancements - COMPLETE

#### Router Changes (Complete)

New routes added to `lib/switch_telemetry_web/router.ex`:
- `GET /devices/:id/edit` - DeviceLive.Edit
- `GET /devices/:id/subscriptions` - SubscriptionLive.Index
- `GET /credentials` - CredentialLive.Index
- `GET /credentials/:id` - CredentialLive.Show
- `GET /streams` - StreamLive.Monitor

#### Context Functions (Complete)

Added to `lib/switch_telemetry/devices.ex`:
- `list_credentials/0` - List all credentials
- `list_credentials_for_select/0` - For dropdown options
- `get_device_with_credential!/1` - Preload credential
- `get_device_with_subscriptions!/1` - Preload subscriptions
- `change_device/2` - Device changeset helper
- `change_credential/2` - Credential changeset helper

#### LiveView Modules (Complete)

| File | Purpose | Status |
|------|---------|--------|
| `lib/switch_telemetry_web/live/device_live/edit.ex` | Device edit form | Complete |
| `lib/switch_telemetry_web/live/credential_live/index.ex` | Credential list page | Complete |
| `lib/switch_telemetry_web/live/credential_live/show.ex` | Credential detail page | Complete |

### Phase 3: Subscription Management - COMPLETE

| File | Purpose | Status |
|------|---------|--------|
| `lib/switch_telemetry_web/live/subscription_live/index.ex` | Per-device subscription list | Complete |

### Phase 4: Stream Monitoring - COMPLETE

| File | Purpose | Status |
|------|---------|--------|
| `lib/switch_telemetry_web/live/stream_live/monitor.ex` | Cluster-wide stream overview | Complete |
| `lib/switch_telemetry/collector/stream_monitor.ex` | GenServer for session status aggregation | Complete |

## File Summary

### New Files (14)
```
lib/switch_telemetry_web/components/
  sidebar.ex
  top_bar.ex
  mobile_nav.ex

lib/switch_telemetry_web/live/
  device_live/
    edit.ex
  credential_live/
    index.ex
    show.ex
  subscription_live/
    index.ex
  stream_live/
    monitor.ex

lib/switch_telemetry/collector/
  stream_monitor.ex
  collector.ex

test/
  switch_telemetry/collector_test.exs
  switch_telemetry/collector/stream_monitor_test.exs
```

### Modified Files (8)
```
lib/switch_telemetry/application.ex
lib/switch_telemetry/devices.ex
lib/switch_telemetry_web/components/core_components.ex
lib/switch_telemetry_web/components/layouts/app.html.heex
lib/switch_telemetry_web/router.ex
lib/switch_telemetry_web/user_auth.ex
lib/switch_telemetry_web/live/device_live/index.ex
lib/switch_telemetry_web/live/device_live/show.ex
```

## Verification

1. **Layout & Navigation:**
   - Run `mix phx.server`
   - Verify sidebar renders with correct nav items
   - Test responsive behavior at different breakpoints
   - Verify active state highlighting

2. **Routes:**
   - Navigate to `/streams` (new)
   - Navigate to `/credentials` (new)
   - Navigate to `/devices/:id/subscriptions` (new)

3. **Tests:**
   - Run `mix test` to verify no regressions

## Implementation Complete

All planned features have been implemented:
- Modern sidebar navigation with responsive behavior
- Device management with edit functionality
- Credential management UI
- Subscription management per device
- Stream monitoring dashboard
- Updated device LiveViews with edit/subscription links

### Future Enhancements

1. Add FormComponent for SubscriptionLive (inline form editing)
2. Add stream status broadcasts to gnmi_session.ex and netconf_session.ex
3. Add path validation and autocomplete for subscription paths
4. Add bulk device operations (multi-select, batch status change)
