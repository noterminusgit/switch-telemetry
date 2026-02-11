import Config

node_role = System.get_env("NODE_ROLE", "both")

if System.get_env("PHX_SERVER") do
  config :switch_telemetry, SwitchTelemetryWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  pool_size =
    if node_role == "collector" do
      String.to_integer(System.get_env("POOL_SIZE") || "20")
    else
      String.to_integer(System.get_env("POOL_SIZE") || "10")
    end

  config :switch_telemetry, SwitchTelemetry.Repo,
    url: database_url,
    pool_size: pool_size,
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :switch_telemetry, SwitchTelemetryWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]

  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      Generate one with: :crypto.strong_rand_bytes(32) |> Base.encode64()
      """

  config :switch_telemetry, SwitchTelemetry.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key)}
    ]

  # libcluster -- all nodes join the same BEAM cluster
  config :libcluster,
    topologies: [
      dns_poll: [
        strategy: Cluster.Strategy.DNSPoll,
        config: [
          polling_interval: 5_000,
          query: System.get_env("CLUSTER_DNS", "switch-telemetry.internal"),
          node_basename: System.get_env("RELEASE_NAME", "switch_telemetry")
        ]
      ]
    ]

  # Swoosh mailer -- optional SMTP config for alert email notifications
  if smtp_relay = System.get_env("SMTP_RELAY") do
    config :switch_telemetry, SwitchTelemetry.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_relay,
      port: String.to_integer(System.get_env("SMTP_PORT", "587")),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always
  end

  # Oban -- only on collector nodes
  if node_role in ["collector", "both"] do
    config :switch_telemetry, Oban,
      repo: SwitchTelemetry.Repo,
      queues: [
        discovery: 2,
        maintenance: 1,
        notifications: 5,
        alerts: 1
      ]
  else
    config :switch_telemetry, Oban, queues: false
  end
end
