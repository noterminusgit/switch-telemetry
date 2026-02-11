defmodule SwitchTelemetry.Alerting.NotificationChannel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "notification_channels" do
    field :name, :string
    field :type, Ecto.Enum, values: [:webhook, :slack, :email]
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    has_many :channel_bindings, SwitchTelemetry.Alerting.AlertChannelBinding

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id name type config)a
  @optional_fields ~w(enabled)a

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
