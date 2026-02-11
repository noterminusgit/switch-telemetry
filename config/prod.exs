import Config

config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info
