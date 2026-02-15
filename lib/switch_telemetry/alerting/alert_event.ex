defmodule SwitchTelemetry.Alerting.AlertEvent do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "alert_events" do
    field :device_id, :string
    field :status, Ecto.Enum, values: [:firing, :resolved, :acknowledged]
    field :value, :float
    field :message, :string
    field :metadata, :map, default: %{}
    field :inserted_at, :utc_datetime_usec

    belongs_to :alert_rule, SwitchTelemetry.Alerting.AlertRule
  end
end
