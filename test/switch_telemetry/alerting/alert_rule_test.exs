defmodule SwitchTelemetry.Alerting.AlertRuleTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Alerting.AlertRule

  @valid_attrs %{
    id: "rule_test_1",
    name: "High CPU Alert",
    path: "/interfaces/interface/state/counters/in-octets",
    condition: :above,
    threshold: 90.0,
    duration_seconds: 120,
    cooldown_seconds: 300,
    severity: :critical
  }

  describe "changeset/2" do
    test "valid attrs create valid changeset" do
      changeset = AlertRule.changeset(%AlertRule{}, @valid_attrs)
      assert changeset.valid?
    end

    test "name is required" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "path is required" do
      attrs = Map.delete(@valid_attrs, :path)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{path: ["can't be blank"]} = errors_on(changeset)
    end

    test "condition is required" do
      attrs = Map.delete(@valid_attrs, :condition)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{condition: ["can't be blank"]} = errors_on(changeset)
    end

    test "threshold is required when condition is :above" do
      attrs = @valid_attrs |> Map.put(:condition, :above) |> Map.delete(:threshold)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{threshold: ["can't be blank"]} = errors_on(changeset)
    end

    test "threshold is required when condition is :below" do
      attrs = @valid_attrs |> Map.put(:condition, :below) |> Map.delete(:threshold)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{threshold: ["can't be blank"]} = errors_on(changeset)
    end

    test "threshold is required when condition is :rate_increase" do
      attrs = @valid_attrs |> Map.put(:condition, :rate_increase) |> Map.delete(:threshold)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{threshold: ["can't be blank"]} = errors_on(changeset)
    end

    test "threshold is NOT required when condition is :absent" do
      attrs =
        @valid_attrs
        |> Map.put(:condition, :absent)
        |> Map.delete(:threshold)

      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert changeset.valid?
    end

    test "duration_seconds must be greater than 0" do
      attrs = Map.put(@valid_attrs, :duration_seconds, 0)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{duration_seconds: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "duration_seconds rejects negative values" do
      attrs = Map.put(@valid_attrs, :duration_seconds, -10)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{duration_seconds: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "invalid condition is rejected" do
      attrs = Map.put(@valid_attrs, :condition, :nonexistent)
      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert %{condition: ["is invalid"]} = errors_on(changeset)
    end

    test "defaults are applied correctly" do
      attrs = %{
        id: "rule_test_2",
        name: "Default Test",
        path: "/some/path",
        condition: :above,
        threshold: 50.0
      }

      changeset = AlertRule.changeset(%AlertRule{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :duration_seconds) == 60
      assert get_field(changeset, :cooldown_seconds) == 300
      assert get_field(changeset, :severity) == :warning
      assert get_field(changeset, :enabled) == true
      assert get_field(changeset, :state) == :ok
    end
  end
end
