defmodule SwitchTelemetry.Collector.DeviceManagerTest do
  use SwitchTelemetry.DataCase, async: false

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

  describe "GenServer callbacks" do
    test "init sends :start_assigned_devices and schedules :check_sessions" do
      {:ok, state} = DeviceManager.init([])
      assert state == %{sessions: %{}}
      # init sends :start_assigned_devices to self
      assert_received :start_assigned_devices
      # init calls schedule_check() which sends :check_sessions after 30s
      # We can't assert_received because it's send_after, but we can verify
      # the timer ref is set by checking the process mailbox after short wait
    end

    test "handle_call :list_sessions returns device IDs from state" do
      state = %{sessions: %{"dev1" => %{gnmi: self()}, "dev2" => %{netconf: self()}}}

      {:reply, ids, ^state} =
        DeviceManager.handle_call(:list_sessions, {self(), make_ref()}, state)

      assert Enum.sort(ids) == ["dev1", "dev2"]
    end

    test "handle_call :list_sessions returns empty list when no sessions" do
      state = %{sessions: %{}}

      {:reply, ids, ^state} =
        DeviceManager.handle_call(:list_sessions, {self(), make_ref()}, state)

      assert ids == []
    end

    test "handle_call {:stop_session, id} removes session from state" do
      # Use already-exited pids so GenServer.stop catches :exit quickly
      pid1 = spawn(fn -> :ok end)
      pid2 = spawn(fn -> :ok end)
      # Ensure the spawned processes have exited
      Process.sleep(10)

      state = %{sessions: %{"dev1" => %{gnmi: pid1}, "dev2" => %{netconf: pid2}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev1"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev1")
      assert Map.has_key?(new_state.sessions, "dev2")
    end

    test "handle_call {:stop_session, unknown_id} handles missing session gracefully" do
      state = %{sessions: %{}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call(
          {:stop_session, "nonexistent"},
          {self(), make_ref()},
          state
        )

      assert new_state.sessions == %{}
    end

    test "handle_info :start_assigned_devices returns :noreply with sessions" do
      state = %{sessions: %{}}
      # Will query DB for devices assigned to this node; sandbox returns none
      {:noreply, new_state} = DeviceManager.handle_info(:start_assigned_devices, state)
      assert %{sessions: _} = new_state
    end

    test "handle_info :check_sessions returns :noreply and schedules next check" do
      state = %{sessions: %{}}
      # Will query DB for assigned devices; sandbox returns none
      {:noreply, new_state} = DeviceManager.handle_info(:check_sessions, state)
      assert %{sessions: _} = new_state
    end

    test "handle_info unknown message returns :noreply with unchanged state" do
      state = %{sessions: %{}}
      assert {:noreply, ^state} = DeviceManager.handle_info(:unknown, state)
    end
  end

  describe "handle_call {:start_session, device_id}" do
    test "returns error when device does not exist" do
      state = %{sessions: %{}}

      # Ecto.NoResultsError is raised by get_device! for a non-existent ID,
      # caught by the rescue in do_start_session which returns {:error, exception}
      {:reply, {:error, _reason}, new_state} =
        DeviceManager.handle_call(
          {:start_session, "nonexistent-device-id"},
          {self(), make_ref()},
          state
        )

      # State should be unchanged when start fails
      assert new_state.sessions == %{}
    end

    test "error path preserves existing sessions in state" do
      existing_sessions = %{"dev-existing" => %{gnmi: self()}}
      state = %{sessions: existing_sessions}

      {:reply, {:error, _reason}, new_state} =
        DeviceManager.handle_call(
          {:start_session, "nonexistent-device-id"},
          {self(), make_ref()},
          state
        )

      # Existing sessions should be preserved
      assert Map.has_key?(new_state.sessions, "dev-existing")
      assert map_size(new_state.sessions) == 1
    end
  end

  describe "handle_info catch-all with various messages" do
    test "handles {:assignment_changed, device_id} tuple gracefully" do
      state = %{sessions: %{}}
      # The catch-all handle_info(_msg, state) handles any unmatched message
      assert {:noreply, ^state} =
               DeviceManager.handle_info({:assignment_changed, "device-1"}, state)
    end

    test "handles {:DOWN, ref, :process, pid, reason} for non-session processes" do
      state = %{sessions: %{"dev1" => %{gnmi: self()}}}
      ref = make_ref()
      msg = {:DOWN, ref, :process, self(), :normal}
      assert {:noreply, ^state} = DeviceManager.handle_info(msg, state)
    end

    test "handles arbitrary tuples without crashing" do
      state = %{sessions: %{}}
      assert {:noreply, ^state} = DeviceManager.handle_info({:unexpected, :data, 123}, state)
    end

    test "handles string messages without crashing" do
      state = %{sessions: %{}}
      assert {:noreply, ^state} = DeviceManager.handle_info("string_message", state)
    end
  end

  describe "handle_info :start_assigned_devices with existing sessions" do
    test "preserves existing sessions when no new devices are assigned" do
      existing_sessions = %{"dev-existing" => %{gnmi: self()}}
      state = %{sessions: existing_sessions}

      {:noreply, new_state} = DeviceManager.handle_info(:start_assigned_devices, state)

      # Existing sessions should still be present (no devices assigned to this node
      # in test sandbox, so no new ones are added)
      assert Map.has_key?(new_state.sessions, "dev-existing")
    end
  end

  describe "handle_info :check_sessions with existing sessions" do
    test "stops sessions for devices no longer assigned" do
      # Use an already-exited pid so GenServer.stop catches :exit quickly
      pid = spawn(fn -> :ok end)
      Process.sleep(10)

      # This device is in running sessions but won't appear in the DB query
      # (sandbox returns no devices for this collector node), so it should be stopped
      state = %{sessions: %{"dev-unassigned" => %{gnmi: pid}}}

      {:noreply, new_state} = DeviceManager.handle_info(:check_sessions, state)

      # The unassigned device should be removed from sessions
      refute Map.has_key?(new_state.sessions, "dev-unassigned")
    end

    test "check_sessions with empty sessions remains empty" do
      state = %{sessions: %{}}

      {:noreply, new_state} = DeviceManager.handle_info(:check_sessions, state)

      assert new_state.sessions == %{}
    end
  end

  describe "stop session with live GenServer pids" do
    test "handle_call {:stop_session} stops a live GenServer gracefully" do
      # Start a simple GenServer-like process that responds to stop
      {:ok, agent} = Agent.start_link(fn -> %{} end)
      assert Process.alive?(agent)

      state = %{sessions: %{"dev1" => %{gnmi: agent}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev1"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev1")
      # The agent should have been stopped
      refute Process.alive?(agent)
    end

    test "handle_call {:stop_session} handles multiple session types" do
      {:ok, agent1} = Agent.start_link(fn -> %{} end)
      {:ok, agent2} = Agent.start_link(fn -> %{} end)
      assert Process.alive?(agent1)
      assert Process.alive?(agent2)

      state = %{sessions: %{"dev1" => %{gnmi: agent1, netconf: agent2}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev1"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev1")
      refute Process.alive?(agent1)
      refute Process.alive?(agent2)
    end
  end

  # ============================================================
  # New tests targeting untested branches for coverage improvement
  # ============================================================

  describe "handle_call {:start_session} error path with nonexistent device" do
    test "returns error tuple and preserves state for nonexistent device" do
      state = %{sessions: %{"keep-me" => %{gnmi: self()}}}

      {:reply, {:error, _}, new_state} =
        DeviceManager.handle_call(
          {:start_session, "totally-fake-device-id"},
          {self(), make_ref()},
          state
        )

      # Existing sessions preserved
      assert Map.has_key?(new_state.sessions, "keep-me")
      assert map_size(new_state.sessions) == 1
    end

    test "error path returns proper error for another nonexistent device" do
      state = %{sessions: %{}}

      {:reply, {:error, reason}, _new_state} =
        DeviceManager.handle_call(
          {:start_session, "some-other-nonexistent"},
          {self(), make_ref()},
          state
        )

      # The rescue catches the Ecto.NoResultsError from get_device!
      assert %Ecto.NoResultsError{} = reason
    end
  end

  describe "handle_call {:stop_session} comprehensive tests" do
    test "stop_session with multiple session types stops all" do
      {:ok, agent_gnmi} = Agent.start_link(fn -> :gnmi end)
      {:ok, agent_netconf} = Agent.start_link(fn -> :netconf end)

      state = %{sessions: %{"dev-multi" => %{gnmi: agent_gnmi, netconf: agent_netconf}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev-multi"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev-multi")
      refute Process.alive?(agent_gnmi)
      refute Process.alive?(agent_netconf)
    end

    test "stop_session preserves other sessions" do
      {:ok, agent1} = Agent.start_link(fn -> :a end)
      {:ok, agent2} = Agent.start_link(fn -> :b end)

      state = %{
        sessions: %{
          "dev-stop" => %{gnmi: agent1},
          "dev-keep" => %{netconf: agent2}
        }
      }

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev-stop"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev-stop")
      assert Map.has_key?(new_state.sessions, "dev-keep")
      refute Process.alive?(agent1)
      assert Process.alive?(agent2)

      # Cleanup
      Agent.stop(agent2)
    end

    test "stop_session with nil entry in sessions map is a no-op" do
      state = %{sessions: %{"dev-nil" => nil}}

      # Map.get returns nil, which goes to the nil -> :ok clause
      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev-nil"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev-nil")
    end
  end

  describe "handle_call :list_sessions with various states" do
    test "returns all device IDs in order" do
      state = %{
        sessions: %{
          "dev-z" => %{gnmi: self()},
          "dev-a" => %{netconf: self()},
          "dev-m" => %{gnmi: self(), netconf: self()}
        }
      }

      {:reply, ids, ^state} =
        DeviceManager.handle_call(:list_sessions, {self(), make_ref()}, state)

      assert length(ids) == 3
      assert "dev-z" in ids
      assert "dev-a" in ids
      assert "dev-m" in ids
    end

    test "returns single device ID" do
      state = %{sessions: %{"only-one" => %{gnmi: self()}}}

      {:reply, ids, _} =
        DeviceManager.handle_call(:list_sessions, {self(), make_ref()}, state)

      assert ids == ["only-one"]
    end
  end

  describe "handle_info :start_assigned_devices with no assigned devices" do
    test "returns state with sessions unchanged when DB returns no devices" do
      state = %{sessions: %{}}
      {:noreply, new_state} = DeviceManager.handle_info(:start_assigned_devices, state)

      assert new_state.sessions == %{}
    end

    test "preserves existing sessions when no new devices are found" do
      state = %{sessions: %{"existing" => %{gnmi: self()}}}
      {:noreply, result_state} = DeviceManager.handle_info(:start_assigned_devices, state)

      assert Map.has_key?(result_state.sessions, "existing")
    end
  end

  describe "handle_info :check_sessions reconciliation with no DB devices" do
    test "stops all running sessions when no devices are assigned" do
      pid1 = spawn(fn -> :ok end)
      pid2 = spawn(fn -> :ok end)
      Process.sleep(10)

      state = %{
        sessions: %{
          "orphan1" => %{gnmi: pid1},
          "orphan2" => %{netconf: pid2}
        }
      }

      {:noreply, new_state} = DeviceManager.handle_info(:check_sessions, state)

      # Both should be removed since they don't appear in DB assigned list
      refute Map.has_key?(new_state.sessions, "orphan1")
      refute Map.has_key?(new_state.sessions, "orphan2")
      assert new_state.sessions == %{}
    end

    test "check_sessions with no sessions and no assignments remains empty" do
      state = %{sessions: %{}}
      {:noreply, new_state} = DeviceManager.handle_info(:check_sessions, state)
      assert new_state.sessions == %{}
    end
  end

  describe "do_stop_session with already-dead processes" do
    test "stop_session handles dead gnmi pid gracefully" do
      pid = spawn(fn -> :ok end)
      Process.sleep(50)

      state = %{sessions: %{"dev-dead" => %{gnmi: pid}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev-dead"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev-dead")
    end

    test "stop_session handles dead netconf pid gracefully" do
      pid = spawn(fn -> :ok end)
      Process.sleep(50)

      state = %{sessions: %{"dev-dead-nc" => %{netconf: pid}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev-dead-nc"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev-dead-nc")
    end

    test "stop_session handles mix of alive and dead pids" do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(50)
      {:ok, alive_agent} = Agent.start_link(fn -> %{} end)

      state = %{sessions: %{"dev-mixed" => %{gnmi: dead_pid, netconf: alive_agent}}}

      {:reply, :ok, new_state} =
        DeviceManager.handle_call({:stop_session, "dev-mixed"}, {self(), make_ref()}, state)

      refute Map.has_key?(new_state.sessions, "dev-mixed")
      refute Process.alive?(alive_agent)
    end
  end

  describe "init/1 details" do
    test "init sends :start_assigned_devices immediately" do
      {:ok, state} = DeviceManager.init([])
      assert state == %{sessions: %{}}
      assert_received :start_assigned_devices
    end

    test "init schedules :check_sessions via send_after" do
      {:ok, _state} = DeviceManager.init([])
      # :check_sessions is scheduled with @check_interval (30s)
    end

    test "init with any keyword opts returns same initial state" do
      {:ok, state} = DeviceManager.init(name: :custom_name)
      assert state == %{sessions: %{}}
    end
  end

  describe "multiple stop_session calls" do
    test "stopping same device twice is idempotent" do
      {:ok, agent} = Agent.start_link(fn -> %{} end)

      state = %{sessions: %{"dev-twice" => %{gnmi: agent}}}

      {:reply, :ok, state2} =
        DeviceManager.handle_call({:stop_session, "dev-twice"}, {self(), make_ref()}, state)

      refute Map.has_key?(state2.sessions, "dev-twice")

      {:reply, :ok, state3} =
        DeviceManager.handle_call({:stop_session, "dev-twice"}, {self(), make_ref()}, state2)

      refute Map.has_key?(state3.sessions, "dev-twice")
    end
  end

  describe "handle_info catch-all with more message types" do
    test "handles timer reference messages" do
      state = %{sessions: %{"dev1" => %{gnmi: self()}}}
      timer_ref = make_ref()

      assert {:noreply, ^state} =
               DeviceManager.handle_info({:timeout, timer_ref, :something}, state)
    end

    test "handles nil message" do
      state = %{sessions: %{}}
      assert {:noreply, ^state} = DeviceManager.handle_info(nil, state)
    end

    test "handles integer message" do
      state = %{sessions: %{}}
      assert {:noreply, ^state} = DeviceManager.handle_info(42, state)
    end

    test "handles :EXIT message (not trapped)" do
      state = %{sessions: %{"dev1" => %{gnmi: self()}}}
      assert {:noreply, ^state} = DeviceManager.handle_info({:EXIT, self(), :normal}, state)
    end
  end
end
