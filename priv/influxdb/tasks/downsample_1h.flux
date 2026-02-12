// Downsample raw metrics into 1-hour aggregates.
// Runs every hour, processes data from the last 2 hours
// to ensure late-arriving data is captured.
option task = {name: "downsample_1h", every: 1h, offset: 5m}

from(bucket: "metrics_raw")
    |> range(start: -2h)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 1h, fn: mean, createEmpty: false)
    |> set(key: "_field", value: "avg_value")
    |> to(bucket: "metrics_1h", org: "switch-telemetry")

from(bucket: "metrics_raw")
    |> range(start: -2h)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 1h, fn: max, createEmpty: false)
    |> set(key: "_field", value: "max_value")
    |> to(bucket: "metrics_1h", org: "switch-telemetry")

from(bucket: "metrics_raw")
    |> range(start: -2h)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 1h, fn: min, createEmpty: false)
    |> set(key: "_field", value: "min_value")
    |> to(bucket: "metrics_1h", org: "switch-telemetry")

from(bucket: "metrics_raw")
    |> range(start: -2h)
    |> filter(fn: (r) => r._measurement == "metrics")
    |> filter(fn: (r) => r._field == "value_float")
    |> aggregateWindow(every: 1h, fn: count, createEmpty: false)
    |> set(key: "_field", value: "sample_count")
    |> to(bucket: "metrics_1h", org: "switch-telemetry")
