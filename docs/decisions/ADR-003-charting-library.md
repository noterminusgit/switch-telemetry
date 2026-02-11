# ADR-003: VegaLite/Tucan for Interactive Client-Side Charting

**Status:** Accepted (supersedes original Plox decision)
**Date:** 2026-02-10

## Context

Dashboards need interactive charts for time-series data (line charts, bar charts, area fills). The charts must update in real-time as new telemetry arrives via PubSub. Users need to explore data with tooltips, zoom, and pan.

## Decision

Use **VegaLite** (`{:vega_lite, "~> 0.1"}`) and **Tucan** (`{:tucan, "~> 0.5"}`) for client-side interactive chart rendering within Phoenix LiveView, powered by the Vega JavaScript runtime.

## Rationale

- **Rich interactivity out of the box**: Tooltips, zoom, pan, brush selections, and cross-filtering are built into Vega-Lite. No custom JavaScript needed for these features -- they're declarative in the spec.
- **Grammar of graphics**: Vega-Lite's declarative approach makes it easy to compose complex multi-series charts with independent axes, layered marks, and faceted views -- essential for network telemetry dashboards comparing multiple interfaces or devices.
- **Tucan high-level API**: Tucan wraps VegaLite with a seaborn-style API (`Tucan.lineplot/3`, `Tucan.area/3`, etc.) that reduces boilerplate. Specs can still be customized via the underlying VegaLite pipeline.
- **Massive ecosystem**: VegaLite has 1M+ hex downloads. Vega-Lite (the JS grammar) has extensive documentation and a huge gallery of examples. Well-tested across many production systems.
- **Temporal encoding**: Native datetime axis handling with automatic tick formatting, time unit aggregation, and timezone support -- critical for telemetry time-series.
- **LiveView integration**: JSON specs are pushed via `push_event/3` to a lightweight JavaScript hook. The hook calls `vegaEmbed()` to render. Updates push a new spec or stream data points.

## Alternatives Considered

### Plox (server-side SVG)
**Pros**: Pure Elixir, no JavaScript dependency, leverages LiveView DOM diffing for updates.
**Cons**: Very young library (v0.2.1, ~3.4k downloads). No built-in interactivity (tooltips, zoom, pan require custom JS). Limited chart types. Large SVG DOM for many data points.
**Rejected**: The lack of built-in interactivity is a significant limitation for a data exploration dashboard. Users need to zoom into time ranges, hover for exact values, and compare series -- all of which require custom JavaScript with Plox, negating its "no JS" advantage.

### Contex
**Pros**: Pure Elixir, server-side SVG.
**Cons**: Limited documentation, fewer chart types, less active development.
**Rejected**: Same interactivity limitations as Plox, with a less active project.

### Client-side JS library (Chart.js, ApexCharts) via hooks
**Pros**: Rich interactivity, huge ecosystem, well-documented.
**Cons**: Imperative API requires significant custom JavaScript for each chart type. No Elixir-side spec generation -- chart configuration lives in JS, not in LiveView.
**Rejected**: VegaLite/Tucan gives us the same interactivity but with specs generated entirely in Elixir. The declarative approach is a better fit for LiveView's server-driven model.

## Consequences

### Positive
- Built-in tooltips, zoom, pan, and selections without custom JavaScript
- Declarative specs generated in Elixir, pushed to browser as JSON
- Huge chart type variety via Tucan (line, bar, area, scatter, heatmap, boxplot, histogram, etc.)
- Well-documented grammar with extensive example gallery
- Independent axes for multi-metric charts (e.g., bandwidth + error rate on same chart)

### Negative
- Requires JavaScript bundle (~200-500KB for Vega runtime). Mitigation: lazy-load on dashboard pages, CDN in production, browser caches after first load
- Client-side rendering adds latency vs immediate SVG display. Mitigation: acceptable for dashboard use case, specs are small JSON payloads
- Requires npm packages (vega, vega-lite, vega-embed) in the assets pipeline. Mitigation: standard Phoenix asset management, pinned versions
- Full spec re-push on data update (vs LiveView SVG diffing). Mitigation: throttle updates to ~1-2 Hz for human perception, keep data points under 1000 per series
