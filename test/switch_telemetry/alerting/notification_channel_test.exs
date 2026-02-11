defmodule SwitchTelemetry.Alerting.NotificationChannelTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Alerting.NotificationChannel

  @valid_attrs %{
    id: "chan_test_1",
    name: "Ops Webhook",
    type: :webhook,
    config: %{"url" => "https://hooks.example.com/alert"}
  }

  describe "changeset/2" do
    test "valid attrs create valid changeset" do
      changeset = NotificationChannel.changeset(%NotificationChannel{}, @valid_attrs)
      assert changeset.valid?
    end

    test "name is required" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "type is required" do
      attrs = Map.delete(@valid_attrs, :type)
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "config is required" do
      attrs = Map.put(@valid_attrs, :config, nil)
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert %{config: ["can't be blank"]} = errors_on(changeset)
    end

    test "webhook is a valid type" do
      attrs = Map.put(@valid_attrs, :type, :webhook)
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert changeset.valid?
    end

    test "slack is a valid type" do
      attrs = %{@valid_attrs | id: "chan_test_2", name: "Slack Channel", type: :slack}
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert changeset.valid?
    end

    test "email is a valid type" do
      attrs = %{@valid_attrs | id: "chan_test_3", name: "Email Channel", type: :email}
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert changeset.valid?
    end

    test "invalid type is rejected" do
      attrs = Map.put(@valid_attrs, :type, :sms)
      changeset = NotificationChannel.changeset(%NotificationChannel{}, attrs)
      assert %{type: ["is invalid"]} = errors_on(changeset)
    end
  end
end
