defmodule SwitchTelemetry.Metrics.Metric do
  use Ecto.Schema

  @primary_key false
  schema "metrics" do
    field :time, :utc_datetime_usec
    field :device_id, :string
    field :path, :string
    field :source, :string
    field :tags, :map, default: %{}
    field :value_float, :float
    field :value_int, :integer
    field :value_str, :string
  end
end
