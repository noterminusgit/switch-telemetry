defmodule SwitchTelemetry.Alerting.AlertChannelBinding do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "alert_channel_bindings" do
    belongs_to :alert_rule, SwitchTelemetry.Alerting.AlertRule
    belongs_to :notification_channel, SwitchTelemetry.Alerting.NotificationChannel

    field :inserted_at, :utc_datetime_usec
  end

  @required_fields ~w(id alert_rule_id notification_channel_id)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(binding, attrs) do
    binding
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:alert_rule_id)
    |> foreign_key_constraint(:notification_channel_id)
    |> unique_constraint([:alert_rule_id, :notification_channel_id],
      name: :alert_channel_bindings_alert_rule_id_notification_channel_id_in
    )
  end
end
