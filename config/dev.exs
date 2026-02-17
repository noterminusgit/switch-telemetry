import Config

config :switch_telemetry, SwitchTelemetry.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "switch_telemetry_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "/WexLjAVxUhW8z2vKTKH9anh3v7k60WfWCGMOUreQ/xxzQkLwU/TmbQ7rKLd/1MM",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:switch_telemetry, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:switch_telemetry, ~w(--watch)]}
  ]

config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/switch_telemetry_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :switch_telemetry, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
