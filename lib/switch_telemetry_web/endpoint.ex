defmodule SwitchTelemetryWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :switch_telemetry

  @session_options [
    store: :cookie,
    key: "_switch_telemetry_key",
    signing_salt: "KK51uzTY",
    same_site: "Lax",
    http_only: true
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :switch_telemetry,
    gzip: false,
    only: SwitchTelemetryWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :switch_telemetry
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SwitchTelemetryWeb.Router
end
