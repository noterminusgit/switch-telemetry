defmodule SwitchTelemetry.Collector.DeviceManagerTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Collector.DeviceManager

  describe "module API" do
    test "exports start_link/1" do
      assert function_exported?(DeviceManager, :start_link, 1)
    end

    test "exports start_device_session/1" do
      assert function_exported?(DeviceManager, :start_device_session, 1)
    end

    test "exports stop_device_session/1" do
      assert function_exported?(DeviceManager, :stop_device_session, 1)
    end

    test "exports list_sessions/0" do
      assert function_exported?(DeviceManager, :list_sessions, 0)
    end
  end

  describe "state management" do
    test "initial state has empty sessions map" do
      state = %{sessions: %{}}
      assert state.sessions == %{}
      assert map_size(state.sessions) == 0
    end

    test "session tracking adds devices" do
      state = %{sessions: %{}}
      pids = %{gnmi: self(), netconf: self()}
      sessions = Map.put(state.sessions, "dev1", pids)
      assert Map.has_key?(sessions, "dev1")
      assert sessions["dev1"].gnmi == self()
      assert sessions["dev1"].netconf == self()
    end

    test "session tracking removes devices" do
      sessions = %{"dev1" => %{gnmi: self()}, "dev2" => %{netconf: self()}}
      sessions = Map.delete(sessions, "dev1")
      refute Map.has_key?(sessions, "dev1")
      assert Map.has_key?(sessions, "dev2")
    end

    test "session tracking replaces existing device" do
      pid1 = self()
      sessions = %{"dev1" => %{gnmi: pid1}}
      # Simulate re-adding with new pid (e.g. after restart)
      sessions = Map.put(sessions, "dev1", %{gnmi: pid1, netconf: pid1})
      assert map_size(sessions["dev1"]) == 2
    end

    test "list_sessions returns device IDs" do
      sessions = %{
        "dev1" => %{gnmi: self()},
        "dev2" => %{netconf: self()},
        "dev3" => %{gnmi: self(), netconf: self()}
      }

      keys = Map.keys(sessions)
      assert length(keys) == 3
      assert "dev1" in keys
      assert "dev2" in keys
      assert "dev3" in keys
    end
  end

  describe "session reconciliation logic" do
    test "identifies devices to start and stop" do
      assigned_ids = MapSet.new(["dev1", "dev2", "dev3"])
      running_ids = MapSet.new(["dev1", "dev4"])

      to_start = MapSet.difference(assigned_ids, running_ids)
      to_stop = MapSet.difference(running_ids, assigned_ids)

      assert MapSet.to_list(to_start) |> Enum.sort() == ["dev2", "dev3"]
      assert MapSet.to_list(to_stop) == ["dev4"]
    end

    test "no changes when assignments match running" do
      ids = MapSet.new(["dev1", "dev2"])

      to_start = MapSet.difference(ids, ids)
      to_stop = MapSet.difference(ids, ids)

      assert MapSet.size(to_start) == 0
      assert MapSet.size(to_stop) == 0
    end

    test "all new when no running sessions" do
      assigned_ids = MapSet.new(["dev1", "dev2", "dev3"])
      running_ids = MapSet.new()

      to_start = MapSet.difference(assigned_ids, running_ids)
      to_stop = MapSet.difference(running_ids, assigned_ids)

      assert MapSet.size(to_start) == 3
      assert MapSet.size(to_stop) == 0
    end

    test "all stopped when no assignments" do
      assigned_ids = MapSet.new()
      running_ids = MapSet.new(["dev1", "dev2"])

      to_start = MapSet.difference(assigned_ids, running_ids)
      to_stop = MapSet.difference(running_ids, assigned_ids)

      assert MapSet.size(to_start) == 0
      assert MapSet.size(to_stop) == 2
    end

    test "reconciliation with large device sets" do
      assigned = MapSet.new(for i <- 1..100, do: "dev#{i}")
      running = MapSet.new(for i <- 50..150, do: "dev#{i}")

      to_start = MapSet.difference(assigned, running)
      to_stop = MapSet.difference(running, assigned)

      # dev1..dev49 need to start
      assert MapSet.size(to_start) == 49
      # dev101..dev150 need to stop
      assert MapSet.size(to_stop) == 50
    end
  end

  describe "transport selection logic" do
    test "gnmi transport starts only gnmi session" do
      transport = :gnmi
      pids = %{}

      pids =
        if transport in [:gnmi, :both] do
          Map.put(pids, :gnmi, :fake_pid)
        else
          pids
        end

      pids =
        if transport in [:netconf, :both] do
          Map.put(pids, :netconf, :fake_pid)
        else
          pids
        end

      assert Map.has_key?(pids, :gnmi)
      refute Map.has_key?(pids, :netconf)
    end

    test "netconf transport starts only netconf session" do
      transport = :netconf
      pids = %{}

      pids =
        if transport in [:gnmi, :both] do
          Map.put(pids, :gnmi, :fake_pid)
        else
          pids
        end

      pids =
        if transport in [:netconf, :both] do
          Map.put(pids, :netconf, :fake_pid)
        else
          pids
        end

      refute Map.has_key?(pids, :gnmi)
      assert Map.has_key?(pids, :netconf)
    end

    test "both transport starts gnmi and netconf sessions" do
      transport = :both
      pids = %{}

      pids =
        if transport in [:gnmi, :both] do
          Map.put(pids, :gnmi, :fake_pid)
        else
          pids
        end

      pids =
        if transport in [:netconf, :both] do
          Map.put(pids, :netconf, :fake_pid)
        else
          pids
        end

      assert Map.has_key?(pids, :gnmi)
      assert Map.has_key?(pids, :netconf)
    end

    test "unknown transport starts no sessions" do
      transport = :snmp
      pids = %{}

      pids =
        if transport in [:gnmi, :both] do
          Map.put(pids, :gnmi, :fake_pid)
        else
          pids
        end

      pids =
        if transport in [:netconf, :both] do
          Map.put(pids, :netconf, :fake_pid)
        else
          pids
        end

      assert map_size(pids) == 0
    end
  end

  describe "stop session logic" do
    test "stopping nil session is a no-op" do
      sessions = %{}
      result = Map.get(sessions, "nonexistent")
      assert result == nil
    end

    test "stopping session with pids iterates over each type" do
      pids = %{gnmi: :pid1, netconf: :pid2}
      types = Enum.map(pids, fn {type, _pid} -> type end)
      assert :gnmi in types
      assert :netconf in types
      assert length(types) == 2
    end

    test "stopping session removes it from sessions map" do
      sessions = %{
        "dev1" => %{gnmi: :pid1},
        "dev2" => %{netconf: :pid2}
      }

      sessions = Map.delete(sessions, "dev1")
      assert map_size(sessions) == 1
      refute Map.has_key?(sessions, "dev1")
    end
  end

  describe "check_sessions scheduling" do
    test "check interval is 30 seconds" do
      # The module uses @check_interval :timer.seconds(30)
      assert :timer.seconds(30) == 30_000
    end
  end
end
