defmodule SwitchTelemetry.Devices.Credential do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "credentials" do
    field :name, :string
    field :username, :string
    field :password, :string
    field :ssh_key, :string
    field :tls_cert, :string
    field :tls_key, :string

    has_many :devices, SwitchTelemetry.Devices.Device

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id name username)a
  @optional_fields ~w(password ssh_key tls_cert tls_key)a

  def changeset(credential, attrs) do
    credential
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
