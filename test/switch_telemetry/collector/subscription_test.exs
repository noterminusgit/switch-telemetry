defmodule SwitchTelemetry.Collector.SubscriptionTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.Subscription

  @valid_attrs %{
    id: "sub_test001",
    device_id: "dev_test001",
    paths: ["/interfaces/interface/state/counters", "/system/cpu/state"]
  }

  describe "changeset/2" do
    test "valid attributes" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires paths" do
      attrs = Map.delete(@valid_attrs, :paths)
      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{paths: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires at least one path" do
      attrs = Map.put(@valid_attrs, :paths, [])
      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert %{paths: ["should have at least 1 item(s)"]} = errors_on(changeset)
    end

    test "defaults mode to stream" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :mode) == :stream
    end

    test "defaults encoding to proto" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :encoding) == :proto
    end

    test "defaults enabled to true" do
      changeset = Subscription.changeset(%Subscription{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :enabled) == true
    end
  end
end
