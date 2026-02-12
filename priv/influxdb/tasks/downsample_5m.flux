// Downsample raw metrics into 5-minute aggregates.
// Runs every 5 minutes, processes data from the last 10 minutes
// to ensure late-arriving data is captured.
option task = {name: "downsample_5m", every: 5m, offset: 1m}

from(bucket: "metrics_raw")
    |> range(start: -10m)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 5m, fn: mean, createEmpty: false)
    |> set(key: "_field", value: "avg_value")
    |> to(bucket: "metrics_5m", org: "switch-telemetry")

from(bucket: "metrics_raw")
    |> range(start: -10m)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 5m, fn: max, createEmpty: false)
    |> set(key: "_field", value: "max_value")
    |> to(bucket: "metrics_5m", org: "switch-telemetry")

from(bucket: "metrics_raw")
    |> range(start: -10m)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 5m, fn: min, createEmpty: false)
    |> set(key: "_field", value: "min_value")
    |> to(bucket: "metrics_5m", org: "switch-telemetry")

from(bucket: "metrics_raw")
    |> range(start: -10m)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 5m, fn: count, createEmpty: false)
    |> set(key: "_field", value: "sample_count")
    |> to(bucket: "metrics_5m", org: "switch-telemetry")
