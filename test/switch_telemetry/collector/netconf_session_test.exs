defmodule SwitchTelemetry.Collector.NetconfSessionTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.NetconfSession

  describe "struct" do
    test "default state" do
      state = %NetconfSession{}
      assert state.device == nil
      assert state.ssh_ref == nil
      assert state.channel_id == nil
      assert state.buffer == ""
      assert state.message_id == 1
    end
  end

  describe "child_spec" do
    test "start_link requires device option" do
      assert_raise KeyError, fn ->
        NetconfSession.start_link([])
      end
    end
  end
end
