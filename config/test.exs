import Config

config :switch_telemetry, SwitchTelemetry.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "switch_telemetry_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "znFtCbpblDrerRpgkl2i8Rsgvk0dp1ItmNwQopj4BuNyX8bSQFiep9NcOk2bg3KL",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :switch_telemetry, Oban, testing: :inline
