defmodule SwitchTelemetry.MixProject do
  use Mix.Project

  def project do
    [
      app: :switch_telemetry,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        ignore_modules: [
          # Protobuf-generated modules (gnmi.pb.ex / gnmi.service.ex)
          Gnmi.CapabilityRequest,
          Gnmi.CapabilityResponse,
          Gnmi.Encoding,
          Gnmi.GetRequest,
          Gnmi.GetRequest.DataType,
          Gnmi.GetResponse,
          Gnmi.GNMI.Service,
          Gnmi.GNMI.Stub,
          Gnmi.Notification,
          Gnmi.Path,
          Gnmi.PathElem,
          Gnmi.SetRequest,
          Gnmi.SetResponse,
          Gnmi.SubscribeRequest,
          Gnmi.SubscribeResponse,
          Gnmi.Subscription,
          Gnmi.SubscriptionList,
          Gnmi.SubscriptionList.Mode,
          Gnmi.SubscriptionMode,
          Gnmi.TypedValue,
          Gnmi.Update,
          Gnmi.UpdateResult,
          Gnmi.PathElem.KeyEntry,
          Gnmi.Poll,
          Gnmi.QOS,
          Gnmi.SubscriptionListMode,
          # Inspect protocol derivations (auto-generated)
          Inspect.SwitchTelemetry.Accounts.User,
          Inspect.SwitchTelemetry.Accounts.UserToken,
          Inspect.SwitchTelemetry.Collector.StreamMonitor.StreamStatus,
          Inspect.SwitchTelemetry.Devices.Credential,
          # Test mock module
          SwitchTelemetry.Metrics.MockBackend,
          # Test support modules
          SwitchTelemetry.InfluxCase,
          # Pure struct with no functions
          SwitchTelemetry.Collector.StreamMonitor.StreamStatus,
          # Thin delegation to external libraries (GRPC.Stub, :ssh)
          SwitchTelemetry.Collector.DefaultGrpcClient,
          SwitchTelemetry.Collector.DefaultSshClient,
          # InfluxDB modules (require running InfluxDB instance)
          SwitchTelemetry.Metrics.InfluxBackend,
          SwitchTelemetry.Metrics.QueryRouter,
          SwitchTelemetry.Metrics,
          # Telemetry metrics/poller configuration (infrastructure)
          SwitchTelemetryWeb.Telemetry,
          # Template-only modules (embed_templates, no logic)
          SwitchTelemetryWeb.Layouts,
          SwitchTelemetryWeb.UserSessionHTML
        ]
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [
      mod: {SwitchTelemetry.Application, []},
      extra_applications: [:logger, :runtime_tools, :ssh]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Web
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:heroicons, "~> 0.5"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},

      # Database
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:instream, "~> 2.2"},

      # Charting
      {:vega_lite, "~> 0.1"},
      {:tucan, "~> 0.5"},
      {:vega_lite_convert, "~> 1.0"},

      # Protocols
      {:grpc, "~> 0.9"},
      {:protobuf, "~> 0.14"},
      {:sweet_xml, "~> 0.7"},

      # Distribution
      {:libcluster, "~> 3.4"},
      {:horde, "~> 0.9"},

      # Background jobs
      {:oban, "~> 2.17"},

      # Security
      {:bcrypt_elixir, "~> 3.0"},
      {:cloak_ecto, "~> 1.3"},

      # Notifications
      {:finch, "~> 0.18"},
      {:swoosh, "~> 1.16"},

      # Utilities
      {:jason, "~> 1.4"},
      {:hash_ring, "~> 0.4"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:plug_cowboy, "~> 2.7"},
      {:dns_cluster, "~> 0.1"},
      {:bandit, "~> 1.0"},

      # Testing & Analysis
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp releases do
    [
      collector: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble]
      ],
      web: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild switch_telemetry"],
      "assets.deploy": ["esbuild switch_telemetry --minify", "phx.digest"]
    ]
  end
end
