defmodule SwitchTelemetry.Settings.SecuritySetting do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "security_settings" do
    field :require_secure_gnmi, :boolean, default: false
    field :require_credentials, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @fields [:require_secure_gnmi, :require_credentials]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(security_setting, attrs) do
    security_setting
    |> cast(attrs, @fields)
  end
end
