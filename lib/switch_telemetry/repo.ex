defmodule SwitchTelemetry.Repo do
  use Ecto.Repo,
    otp_app: :switch_telemetry,
    adapter: Ecto.Adapters.Postgres
end
