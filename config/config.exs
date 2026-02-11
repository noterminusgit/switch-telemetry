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
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

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

import_config "#{config_env()}.exs"
