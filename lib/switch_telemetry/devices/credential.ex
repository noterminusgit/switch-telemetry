defmodule SwitchTelemetry.Devices.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  @derive {Inspect, except: [:password, :ssh_key, :tls_key, :ca_cert]}
  schema "credentials" do
    field :name, :string
    field :username, :string
    field :password, SwitchTelemetry.Encrypted.Binary
    field :ssh_key, SwitchTelemetry.Encrypted.Binary
    field :tls_cert, SwitchTelemetry.Encrypted.Binary
    field :tls_key, SwitchTelemetry.Encrypted.Binary
    field :ca_cert, SwitchTelemetry.Encrypted.Binary

    has_many :devices, SwitchTelemetry.Devices.Device

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id name username)a
  @optional_fields ~w(password ssh_key tls_cert tls_key ca_cert)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 255)
    |> validate_length(:username, max: 255)
    |> unique_constraint(:name)
  end
end
