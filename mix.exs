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
      listeners: [Phoenix.CodeReloader]
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

      # Testing
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mox, "~> 1.1", only: :test}
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
