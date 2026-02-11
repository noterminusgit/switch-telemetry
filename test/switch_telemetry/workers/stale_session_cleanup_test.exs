defmodule SwitchTelemetry.Workers.StaleSessionCleanupTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Workers.StaleSessionCleanup

  describe "module" do
    test "uses Oban.Worker" do
      assert {:module, StaleSessionCleanup} = Code.ensure_loaded(StaleSessionCleanup)
      assert StaleSessionCleanup.__info__(:functions) |> Keyword.has_key?(:perform)
    end

    test "perform succeeds with no stale sessions" do
      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})
    end
  end
end
