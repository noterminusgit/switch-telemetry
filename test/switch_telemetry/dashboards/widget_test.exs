defmodule SwitchTelemetry.Dashboards.WidgetTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Dashboards.Widget

  @valid_attrs %{
    id: "wgt_test001",
    dashboard_id: "dash_test001",
    title: "Interface Utilization",
    chart_type: :line
  }

  describe "changeset/2 with valid attributes" do
    test "produces a valid changeset with minimal required fields" do
      changeset = Widget.changeset(%Widget{}, @valid_attrs)
      assert changeset.valid?
    end

    test "accepts all valid chart_type enum values" do
      for chart_type <- [:line, :bar, :area, :points, :gauge, :table] do
        attrs = %{@valid_attrs | chart_type: chart_type}
        changeset = Widget.changeset(%Widget{}, attrs)
        assert changeset.valid?, "expected chart_type #{chart_type} to be valid"
      end
    end

    test "sets default position when not provided" do
      changeset = Widget.changeset(%Widget{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :position) == %{x: 0, y: 0, w: 6, h: 4}
    end

    test "sets default time_range when not provided" do
      changeset = Widget.changeset(%Widget{}, @valid_attrs)

      assert Ecto.Changeset.get_field(changeset, :time_range) == %{
               type: "relative",
               duration: "1h"
             }
    end

    test "sets default queries to empty list when not provided" do
      changeset = Widget.changeset(%Widget{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :queries) == []
    end
  end

  describe "changeset/2 with missing required fields" do
    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires dashboard_id" do
      attrs = Map.delete(@valid_attrs, :dashboard_id)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{dashboard_id: ["can't be blank"]} = errors_on(changeset)
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

    test "is invalid when all required fields are missing" do
      changeset = Widget.changeset(%Widget{}, %{})
      errors = errors_on(changeset)
      assert errors[:id]
      assert errors[:dashboard_id]
      assert errors[:title]
      assert errors[:chart_type]
    end
  end

  describe "changeset/2 with invalid chart_type" do
    test "rejects an invalid atom chart_type" do
      attrs = %{@valid_attrs | chart_type: :invalid}
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{chart_type: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects a string chart_type that is not in the enum" do
      attrs = %{@valid_attrs | chart_type: "pie"}
      changeset = Widget.changeset(%Widget{}, attrs)
      assert %{chart_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "changeset/2 with position map" do
    test "accepts a custom position map" do
      attrs = Map.put(@valid_attrs, :position, %{x: 3, y: 2, w: 12, h: 8})
      changeset = Widget.changeset(%Widget{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :position) == %{x: 3, y: 2, w: 12, h: 8}
    end

    test "accepts position with string keys" do
      attrs = Map.put(@valid_attrs, :position, %{"x" => 1, "y" => 1, "w" => 4, "h" => 3})
      changeset = Widget.changeset(%Widget{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 with queries array" do
    test "accepts a non-empty queries list" do
      queries = [
        %{"device_id" => "dev1", "path" => "/interfaces/counters", "field" => "in_octets"},
        %{"device_id" => "dev2", "path" => "/cpu/utilization", "field" => "usage"}
      ]

      attrs = Map.put(@valid_attrs, :queries, queries)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :queries) == queries
    end

    test "accepts an empty queries list" do
      attrs = Map.put(@valid_attrs, :queries, [])
      changeset = Widget.changeset(%Widget{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 with time_range map" do
    test "accepts a custom time_range" do
      time_range = %{type: "absolute", start: "2026-01-01T00:00:00Z", end: "2026-01-02T00:00:00Z"}
      attrs = Map.put(@valid_attrs, :time_range, time_range)
      changeset = Widget.changeset(%Widget{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :time_range) == time_range
    end
  end

  describe "changeset/2 foreign key constraint" do
    test "has a foreign_key_constraint on dashboard_id" do
      changeset = Widget.changeset(%Widget{}, @valid_attrs)
      constraints = changeset.constraints

      assert Enum.any?(constraints, fn c ->
               c.type == :foreign_key && c.field == :dashboard_id
             end)
    end
  end
end
