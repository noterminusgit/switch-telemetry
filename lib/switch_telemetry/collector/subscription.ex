defmodule SwitchTelemetry.Collector.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "subscriptions" do
    field :paths, {:array, :string}
    field :mode, Ecto.Enum, values: [:stream, :poll, :once], default: :stream
    field :sample_interval_ns, :integer, default: 30_000_000_000
    field :encoding, Ecto.Enum, values: [:proto, :json, :json_ietf], default: :proto
    field :enabled, :boolean, default: true

    belongs_to :device, SwitchTelemetry.Devices.Device

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id device_id paths)a
  @optional_fields ~w(mode sample_interval_ns encoding enabled)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:paths, min: 1)
    |> validate_paths()
    |> foreign_key_constraint(:device_id)
  end

  defp validate_paths(changeset) do
    validate_change(changeset, :paths, fn :paths, paths ->
      Enum.flat_map(paths, fn path ->
        cond do
          String.contains?(path, ["<", ">", "&", ";", "--"]) ->
            [paths: "contains invalid characters in path: #{path}"]

          String.length(path) > 512 ->
            [paths: "path too long: #{path}"]

          not String.match?(path, ~r{^/[a-zA-Z0-9/_\-\.:]+$}) ->
            [paths: "invalid path format: #{path}"]

          true ->
            []
        end
      end)
    end)
  end
end
