# Phase 8 Implementation Plan: Advanced Dashboards

## Wave 1: Foundation (parallel agents)

### Agent A: Context + Migration + Clone
1. Create migration: add `tags` column to dashboards
2. Add `clone_dashboard/2` to Dashboards context (deep copy dashboard + widgets)
3. Add `list_device_options/0` helper (returns device id/hostname pairs)
4. Add `list_device_metric_paths/1` helper (distinct paths from metrics table)
5. Tests: clone, device options, metric paths

### Agent B: Router + Dashboard Edit
1. Add new routes: :edit, :add_widget, :edit_widget actions
2. Update DashboardLive.Show to handle :edit action (edit dashboard modal)
3. Handle `update_dashboard` event
4. Add "Clone" button + event to DashboardLive.Index
5. Tests: dashboard edit, clone

## Wave 2: Widget Editor + Time Range (parallel agents)

### Agent C: WidgetEditor LiveComponent
1. Create `lib/switch_telemetry_web/components/widget_editor.ex`
2. Form: title, chart_type select, time_range preset select
3. Query builder: add/remove series (device picker, path input, label, color)
4. Wire into DashboardLive.Show for :add_widget and :edit_widget actions
5. Handle save_widget / update_widget events
6. Tests: add widget, edit widget, delete widget

### Agent D: TimeRangePicker + Export
1. Create `lib/switch_telemetry_web/components/time_range_picker.ex`
2. Relative preset buttons + custom datetime inputs
3. Wire into DashboardLive.Show header
4. Handle `set_time_range` event, reload widget data
5. Update VegaLite JS hook: add `export_png` event handler
6. Add export button to widget cards in Show page
7. Tests: time range selection, data reload
