defmodule SwitchTelemetry.Alerting.AlertRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "alert_rules" do
    field :name, :string
    field :description, :string
    field :path, :string

    field :condition, Ecto.Enum, values: [:above, :below, :absent, :rate_increase]

    field :threshold, :float
    field :duration_seconds, :integer, default: 60
    field :cooldown_seconds, :integer, default: 300

    field :severity, Ecto.Enum,
      values: [:info, :warning, :critical],
      default: :warning

    field :enabled, :boolean, default: true

    field :state, Ecto.Enum,
      values: [:ok, :firing, :acknowledged],
      default: :ok

    field :last_fired_at, :utc_datetime_usec
    field :last_resolved_at, :utc_datetime_usec

    belongs_to :device, SwitchTelemetry.Devices.Device
    belongs_to :creator, SwitchTelemetry.Accounts.User, foreign_key: :created_by
    has_many :events, SwitchTelemetry.Alerting.AlertEvent
    has_many :channel_bindings, SwitchTelemetry.Alerting.AlertChannelBinding

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id name path condition)a
  @optional_fields ~w(description device_id threshold duration_seconds cooldown_seconds severity enabled state last_fired_at last_resolved_at created_by)a

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_length(:path, max: 512)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:cooldown_seconds, greater_than_or_equal_to: 0)
    |> validate_threshold_required()
    |> unique_constraint(:name)
    |> foreign_key_constraint(:device_id)
  end

  defp validate_threshold_required(changeset) do
    condition = get_field(changeset, :condition)

    if condition != :absent do
      validate_required(changeset, [:threshold])
    else
      changeset
    end
  end
end
