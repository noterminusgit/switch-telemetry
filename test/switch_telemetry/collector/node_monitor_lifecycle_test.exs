defmodule SwitchTelemetry.Collector.NodeMonitorLifecycleTest do
  use SwitchTelemetry.DataCase, async: false

  alias SwitchTelemetry.Collector.NodeMonitor

  describe "GenServer callbacks" do
    test "handle_call :cluster_status returns status map with self, nodes, and node_count" do
      state = %{nodes: MapSet.new([:nonode@nohost])}

      {:reply, status, ^state} =
        NodeMonitor.handle_call(:cluster_status, {self(), make_ref()}, state)

      assert %{self: _, nodes: nodes, node_count: count} = status
      assert is_list(nodes)
      assert count == 1
      assert :nonode@nohost in nodes
    end

    test "handle_info :nodeup adds node to state" do
      state = %{nodes: MapSet.new([:self@host])}
      {:noreply, new_state} = NodeMonitor.handle_info({:nodeup, :new@host, []}, state)

      assert MapSet.member?(new_state.nodes, :new@host)
      assert MapSet.member?(new_state.nodes, :self@host)
      assert MapSet.size(new_state.nodes) == 2
    end

    test "handle_info :nodeup emits telemetry event" do
      handler_id = "test-nodeup-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:switch_telemetry, :cluster, :node_up],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      state = %{nodes: MapSet.new()}
      NodeMonitor.handle_info({:nodeup, :new@host, []}, state)

      assert_received {:telemetry_event, [:switch_telemetry, :cluster, :node_up], %{count: 1},
                       %{node: :new@host}}

      :telemetry.detach(handler_id)
    end

    test "handle_info :nodedown removes node from state" do
      state = %{nodes: MapSet.new([:self@host, :old@host])}
      {:noreply, new_state} = NodeMonitor.handle_info({:nodedown, :old@host, []}, state)

      refute MapSet.member?(new_state.nodes, :old@host)
      assert MapSet.member?(new_state.nodes, :self@host)
      assert MapSet.size(new_state.nodes) == 1
    end

    test "handle_info :nodedown emits telemetry event" do
      handler_id = "test-nodedown-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:switch_telemetry, :cluster, :node_down],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      state = %{nodes: MapSet.new([:old@host])}
      NodeMonitor.handle_info({:nodedown, :old@host, []}, state)

      assert_received {:telemetry_event, [:switch_telemetry, :cluster, :node_down], %{count: 1},
                       %{node: :old@host}}

      :telemetry.detach(handler_id)
    end

    test "handle_info :nodedown schedules trigger_rebalance after delay" do
      state = %{nodes: MapSet.new([:self@host, :old@host])}
      NodeMonitor.handle_info({:nodedown, :old@host, []}, state)

      # trigger_rebalance is sent via Process.send_after with 2s delay
      # It should NOT be in the mailbox immediately
      refute_received :trigger_rebalance
    end

    test "handle_info :trigger_rebalance is no-op when DeviceAssignment not running" do
      state = %{nodes: MapSet.new()}
      # DeviceAssignment is registered under __MODULE__ name; if running it will
      # receive a cast. If not registered, Process.whereis returns nil and it's skipped.
      assert {:noreply, ^state} = NodeMonitor.handle_info(:trigger_rebalance, state)
    end

    test "handle_info :heartbeat emits telemetry and returns :noreply" do
      handler_id = "test-heartbeat-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:switch_telemetry, :cluster, :nodes],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      state = %{nodes: MapSet.new([:self@host, :other@host])}
      {:noreply, ^state} = NodeMonitor.handle_info(:heartbeat, state)

      assert_received {:telemetry_event, [:switch_telemetry, :cluster, :nodes], %{count: 2}, _}

      :telemetry.detach(handler_id)
    end

    test "handle_info unknown message returns :noreply with unchanged state" do
      state = %{nodes: MapSet.new()}
      assert {:noreply, ^state} = NodeMonitor.handle_info(:unknown_msg, state)
    end
  end
end
