defmodule SwitchTelemetry.Dashboards.Dashboard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "dashboards" do
    field :name, :string
    field :description, :string
    field :layout, Ecto.Enum, values: [:grid, :freeform], default: :grid
    field :refresh_interval_ms, :integer, default: 5_000
    field :is_public, :boolean, default: false

    has_many :widgets, SwitchTelemetry.Dashboards.Widget

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id name)a
  @optional_fields ~w(description layout refresh_interval_ms is_public)a

  def changeset(dashboard, attrs) do
    dashboard
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:name)
  end
end
