defmodule SwitchTelemetry.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "devices" do
    field :hostname, :string
    field :ip_address, :string

    field :platform, Ecto.Enum,
      values: [:cisco_iosxr, :cisco_iosxe, :cisco_nxos, :juniper_junos, :arista_eos, :nokia_sros]

    field :transport, Ecto.Enum, values: [:gnmi, :netconf, :both]
    field :gnmi_port, :integer, default: 57400
    field :netconf_port, :integer, default: 830
    field :secure_mode, :boolean, default: false
    field :tags, :map, default: %{}
    field :collection_interval_ms, :integer, default: 30_000

    field :status, Ecto.Enum,
      values: [:active, :inactive, :unreachable, :maintenance],
      default: :active

    field :assigned_collector, :string
    field :collector_heartbeat, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec

    belongs_to :credential, SwitchTelemetry.Devices.Credential
    has_many :subscriptions, SwitchTelemetry.Collector.Subscription

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id hostname ip_address platform transport)a
  @optional_fields ~w(gnmi_port netconf_port credential_id tags collection_interval_ms status assigned_collector collector_heartbeat last_seen_at secure_mode)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(device, attrs) do
    device
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_ip_address()
    |> validate_hostname()
    |> validate_inclusion(:gnmi_port, 1..65535)
    |> validate_inclusion(:netconf_port, 1..65535)
    |> validate_length(:ip_address, max: 45)
    |> unique_constraint(:hostname)
    |> unique_constraint(:ip_address)
    |> foreign_key_constraint(:credential_id)
    |> validate_secure_mode()
  end

  @spec validate_secure_mode(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_secure_mode(changeset) do
    secure_mode = get_field(changeset, :secure_mode)
    transport = get_field(changeset, :transport)
    credential_id = get_field(changeset, :credential_id)

    if secure_mode == true and transport in [:gnmi, :both] and
         (is_nil(credential_id) or credential_id == "") do
      add_error(changeset, :credential_id, "is required when secure mode is enabled for gNMI")
    else
      changeset
    end
  end

  defp validate_ip_address(changeset) do
    validate_change(changeset, :ip_address, fn :ip_address, ip ->
      case :inet.parse_address(String.to_charlist(ip)) do
        {:ok, _} -> []
        {:error, _} -> [ip_address: "must be a valid IPv4 or IPv6 address"]
      end
    end)
  end

  defp validate_hostname(changeset) do
    changeset
    |> validate_length(:hostname, max: 253)
    |> validate_format(:hostname, ~r/^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$/,
      message: "must be a valid hostname (RFC 1123)"
    )
  end
end
