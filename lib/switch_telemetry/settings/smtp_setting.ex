defmodule SwitchTelemetry.Settings.SmtpSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "smtp_settings" do
    field :relay, :string
    field :port, :integer, default: 587
    field :username, :string
    field :password, SwitchTelemetry.Encrypted.Binary
    field :from_email, :string, default: "noreply@switch-telemetry.local"
    field :from_name, :string, default: "Switch Telemetry"
    field :tls, :boolean, default: true
    field :enabled, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @fields [:relay, :port, :username, :password, :from_email, :from_name, :tls, :enabled]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(smtp_setting, attrs) do
    smtp_setting
    |> cast(attrs, @fields)
    |> validate_required([:port, :from_email, :from_name])
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> validate_format(:from_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:relay, max: 255)
    |> validate_length(:username, max: 255)
    |> validate_length(:from_email, max: 255)
    |> validate_length(:from_name, max: 255)
  end
end
