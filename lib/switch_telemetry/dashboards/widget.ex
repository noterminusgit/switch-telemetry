defmodule SwitchTelemetry.Dashboards.Widget do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "widgets" do
    field :title, :string
    field :chart_type, Ecto.Enum, values: [:line, :bar, :area, :points, :gauge, :table]
    field :position, :map, default: %{x: 0, y: 0, w: 6, h: 4}
    field :time_range, :map, default: %{type: "relative", duration: "1h"}
    field :queries, {:array, :map}, default: []

    belongs_to :dashboard, SwitchTelemetry.Dashboards.Dashboard

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id dashboard_id title chart_type)a
  @optional_fields ~w(position time_range queries)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(widget, attrs) do
    widget
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:dashboard_id)
  end
end
