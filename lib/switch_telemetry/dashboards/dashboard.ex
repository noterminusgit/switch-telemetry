defmodule SwitchTelemetry.Dashboards.Dashboard do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string
  schema "dashboards" do
    field :name, :string
    field :description, :string
    field :layout, Ecto.Enum, values: [:grid, :freeform], default: :grid
    field :refresh_interval_ms, :integer, default: 5_000
    field :is_public, :boolean, default: false
    field :tags, {:array, :string}, default: []

    belongs_to :creator, SwitchTelemetry.Accounts.User, foreign_key: :created_by
    has_many :widgets, SwitchTelemetry.Dashboards.Widget

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields ~w(id name)a
  @optional_fields ~w(description layout refresh_interval_ms is_public created_by tags)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(dashboard, attrs) do
    dashboard
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:name)
  end
end
