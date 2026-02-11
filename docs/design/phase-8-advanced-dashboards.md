# Phase 8 Design: Advanced Dashboards

## Overview

Enhance the dashboard system with a widget editor, dashboard editing, dashboard cloning, custom time range picker, and chart export. Builds on the existing Dashboard/Widget schemas, TelemetryChart component, and VegaLite JS hook.

## Features

### 1. Dashboard Editing
- Edit dashboard name, description, refresh interval, layout type, public flag
- Inline edit from the Show page header
- Update existing `update_dashboard/2` context function

### 2. Widget Editor
- Add widget form accessible from dashboard Show page
- Edit existing widgets (title, chart type, time range, queries)
- Device picker: select device from dropdown
- Metric path picker: select from known paths for the selected device
- Query builder: add/remove series with device + path + label + color
- Live preview of chart while editing
- Delete widget with confirmation

### 3. Dashboard Cloning
- "Clone Dashboard" button on Index page
- Creates a deep copy: new dashboard + all widgets with new IDs
- Clone name: "Copy of {original name}"
- New `clone_dashboard/2` function in Dashboards context

### 4. Time Range Picker
- Relative presets: 5m, 15m, 1h, 6h, 24h, 7d
- Custom absolute range: start datetime + end datetime pickers
- Global time range on dashboard Show page (applies to all widgets)
- Per-widget time range override option
- Time range stored in URL params for shareability

### 5. Chart Export
- Export individual widget charts as PNG
- VegaLite/Vega supports `view.toImageURL('png')` natively
- Add export button to each widget card
- JavaScript hook handles the download

## Schema Changes

### New Migration: Add `tags` to dashboards
```elixir
alter table(:dashboards) do
  add :tags, {:array, :string}, default: []
end
```

No other schema changes needed — the existing Widget schema with its JSON `queries`, `position`, `time_range` fields is flexible enough.

## Context Changes

### Dashboards Context Additions
```elixir
# Clone a dashboard with all its widgets
clone_dashboard(dashboard, user_id) :: {:ok, Dashboard} | {:error, Changeset}

# List devices for widget query builder
list_device_options() :: [{label, id}]

# List known metric paths for a device
list_device_metric_paths(device_id) :: [String.t()]
```

## LiveView Changes

### DashboardLive.Index
- Add "Clone" button to each dashboard card
- Handle `clone` event

### DashboardLive.Show
- Add "Edit Dashboard" modal/form (name, description, refresh, layout, public)
- Add "Add Widget" button → opens widget editor
- Add time range picker component in header
- Handle `update_dashboard`, `add_widget`, `update_widget` events
- Support `:edit` and `:add_widget` live_actions via router

### New: WidgetEditor LiveComponent
- Form with fields: title, chart_type, time_range
- Query builder: list of series, each with device_id, path, label, color
- Add/remove series buttons
- Live chart preview using TelemetryChart
- Save/cancel actions

### New: TimeRangePicker LiveComponent
- Relative preset buttons (5m, 15m, 1h, 6h, 24h, 7d)
- Custom range form with datetime inputs
- Broadcasts selected range to parent LiveView
- Visual indicator of current selection

## JavaScript Changes

### VegaLite Hook Enhancement
- Add `exportPng` event handler: `view.toImageURL('png')` → trigger download
- Push event from server, hook handles client-side export

## Router Changes

```elixir
# Add to authenticated live_session
live "/dashboards/:id/edit", DashboardLive.Show, :edit
live "/dashboards/:id/widgets/new", DashboardLive.Show, :add_widget
live "/dashboards/:id/widgets/:widget_id/edit", DashboardLive.Show, :edit_widget
```

## Testing Strategy

- Dashboard clone: verify deep copy, new IDs, widget duplication
- Widget CRUD: create, update, delete via LiveView
- Time range picker: relative presets, custom range
- Chart export: verify JS hook event push (can't test actual PNG in ExUnit)
- Dashboard edit: update all fields, verify persistence
