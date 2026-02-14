import Config

config :switch_telemetry,
  ecto_repos: [SwitchTelemetry.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SwitchTelemetryWeb.ErrorHTML, json: SwitchTelemetryWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SwitchTelemetry.PubSub,
  live_view: [signing_salt: "Crj2u5+O"]

config :esbuild,
  version: "0.21.5",
  switch_telemetry: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../assets/node_modules", __DIR__) <> ":" <> Path.expand("../deps", __DIR__)}
  ]

config :tailwind, version: "4.1.12"

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Filter sensitive parameters from logs
config :phoenix, :filter_parameters, [
  "password",
  "secret",
  "token",
  "ssh_key",
  "tls_key",
  "tls_cert",
  "current_password",
  "api_key",
  "cloak_key"
]

# Swoosh mailer (dev/test use local adapter, prod configured in runtime.exs)
config :switch_telemetry, SwitchTelemetry.Mailer, adapter: Swoosh.Adapters.Local

# Oban default config (overridden per environment and by NODE_ROLE in runtime.exs)
config :switch_telemetry, Oban,
  repo: SwitchTelemetry.Repo,
  queues: [default: 10, discovery: 2, maintenance: 1, notifications: 5, alerts: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", SwitchTelemetry.Workers.AlertEvaluator},
       {"0 3 * * *", SwitchTelemetry.Workers.AlertEventPruner}
     ]}
  ]

# Cloak encryption for credentials at rest
config :switch_telemetry, SwitchTelemetry.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("dVFyaWZSNk5hNjRSTmRaUE1UY3dRV2RzNGtHQTZPalk=")}
  ]

# InfluxDB connection for time-series metrics
config :switch_telemetry, SwitchTelemetry.InfluxDB,
  host: "localhost",
  port: 8086,
  scheme: "http",
  auth: [method: :token, token: "dev-token"],
  bucket: "metrics_raw",
  org: "switch-telemetry",
  version: :v2

# Metrics backend module
config :switch_telemetry, :metrics_backend, SwitchTelemetry.Metrics.InfluxBackend

import_config "#{config_env()}.exs"
