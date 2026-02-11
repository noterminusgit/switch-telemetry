defmodule SwitchTelemetry.Dashboards.DashboardTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Dashboards.{Dashboard, Widget}

  describe "Dashboard.changeset/2" do
    @valid_attrs %{id: "dash_test001", name: "DC1 Core Switches"}

    test "valid attributes" do
      changeset = Dashboard.changeset(%Dashboard{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = Dashboard.changeset(%Dashboard{}, attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults layout to grid" do
      changeset = Dashboard.changeset(%Dashboard{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :layout) == :grid
    end

    test "defaults refresh_interval_ms to 5000" do
      changeset = Dashboard.changeset(%Dashboard{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :refresh_interval_ms) == 5_000
    end
  end

  describe "Widget.changeset/2" do
    @valid_attrs %{
      id: "wgt_test001",
      dashboard_id: "dash_test001",
      title: "Interface Utilization",
      chart_type: :line
    }

    test "valid attributes" do
      changeset = Widget.changeset(%Widget{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires title" do
      attrs = Map.delete(@valid_attrs, :title)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires chart_type" do
      attrs = Map.delete(@valid_attrs, :chart_type)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{chart_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates chart_type enum" do
      attrs = Map.put(@valid_attrs, :chart_type, :invalid)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{chart_type: ["is invalid"]} = errors_on(changeset)
    end
  end
end
