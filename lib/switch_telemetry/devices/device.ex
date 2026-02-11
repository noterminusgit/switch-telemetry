defmodule SwitchTelemetry.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "devices" do
    field :hostname, :string
    field :ip_address, :string

    field :platform, Ecto.Enum,
      values: [:cisco_iosxr, :cisco_nxos, :juniper_junos, :arista_eos, :nokia_sros]

    field :transport, Ecto.Enum, values: [:gnmi, :netconf, :both]
    field :gnmi_port, :integer, default: 57400
    field :netconf_port, :integer, default: 830
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
  @optional_fields ~w(gnmi_port netconf_port credential_id tags collection_interval_ms status assigned_collector collector_heartbeat last_seen_at)a

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
