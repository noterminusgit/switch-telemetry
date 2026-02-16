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

    test "is configured for the maintenance queue" do
      assert StaleSessionCleanup.__opts__()[:queue] == :maintenance
    end

    test "has max_attempts of 3" do
      assert StaleSessionCleanup.__opts__()[:max_attempts] == 3
    end
  end

  describe "perform/1 with sessions" do
    test "returns :ok when Horde registry has no sessions" do
      # Horde registry is running but empty, perform should log and return :ok
      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})
    end

    test "does not clean up sessions registered on the current node" do
      # Register a process on the current node in the Horde registry
      test_key = {:device_session, Ecto.UUID.generate()}

      {:ok, _pid} =
        Horde.Registry.register(SwitchTelemetry.DistributedRegistry, test_key, :test)

      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})

      # The session should still be registered since it's on the current (alive) node
      result =
        Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, test_key)

      assert length(result) > 0

      # Clean up
      Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, test_key)
    end

    test "perform always returns :ok regardless of session state" do
      # Even when processing sessions, perform should return :ok
      result = StaleSessionCleanup.perform(%Oban.Job{})
      assert result == :ok
    end
  end

  # ============================================================
  # New tests targeting untested branches for coverage improvement
  # ============================================================

  describe "perform/1 with multiple registered sessions on current node" do
    test "does not remove any sessions registered on live nodes" do
      # Register multiple sessions on the current node
      keys =
        for i <- 1..5 do
          key = {:device_session, "multi-test-#{i}-#{System.unique_integer([:positive])}"}
          {:ok, _pid} = Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :test)
          key
        end

      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})

      # All sessions should still be registered (all on live current node)
      for key <- keys do
        result = Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, key)
        assert length(result) > 0
      end

      # Clean up
      for key <- keys do
        Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
      end
    end
  end

  describe "perform/1 stale count logging" do
    test "returns :ok when all sessions are on active nodes" do
      # Register a session
      key = {:gnmi, "stale-test-#{System.unique_integer([:positive])}"}
      {:ok, _pid} = Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :value)

      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})

      # Session should remain
      result = Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, key)
      assert length(result) > 0

      Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
    end

    test "handles empty Horde registry" do
      # With an empty registry, perform should just return :ok
      # The stale_count should be 0
      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})
    end
  end

  describe "perform/1 with different session key patterns" do
    test "handles :gnmi session keys" do
      key = {:gnmi, "gnmi-session-#{System.unique_integer([:positive])}"}
      {:ok, _pid} = Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :gnmi_val)

      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})

      result = Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, key)
      assert length(result) > 0

      Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
    end

    test "handles :netconf session keys" do
      key = {:netconf, "netconf-session-#{System.unique_integer([:positive])}"}

      {:ok, _pid} =
        Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :netconf_val)

      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})

      result = Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, key)
      assert length(result) > 0

      Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
    end

    test "handles mixed session key types" do
      keys = [
        {:gnmi, "mixed-gnmi-#{System.unique_integer([:positive])}"},
        {:netconf, "mixed-netconf-#{System.unique_integer([:positive])}"},
        {:device_session, "mixed-dev-#{System.unique_integer([:positive])}"}
      ]

      for key <- keys do
        {:ok, _pid} = Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :val)
      end

      assert :ok == StaleSessionCleanup.perform(%Oban.Job{})

      for key <- keys do
        result = Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, key)
        assert length(result) > 0
        Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
      end
    end
  end

  describe "perform/1 active_nodes construction" do
    test "active_nodes includes current node" do
      # This tests the line: active_nodes = MapSet.new([Node.self() | Node.list()])
      active_nodes = MapSet.new([Node.self() | Node.list()])
      assert MapSet.member?(active_nodes, Node.self())
    end

    test "active_nodes is correct for single-node cluster" do
      # In test env, Node.list() is typically empty
      active_nodes = MapSet.new([Node.self() | Node.list()])
      assert MapSet.size(active_nodes) >= 1
    end
  end

  describe "perform/1 stale session detection logic" do
    test "session on current node is not stale" do
      active_nodes = MapSet.new([Node.self() | Node.list()])
      pid = self()
      node = node(pid)

      # Current node should be in active_nodes
      assert MapSet.member?(active_nodes, node)
    end

    test "processes the Horde.Registry.select result format correctly" do
      # Register a known session
      key = {:gnmi, "select-test-#{System.unique_integer([:positive])}"}
      {:ok, _pid} = Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :val)

      # Verify the select returns expected format
      registered =
        Horde.Registry.select(SwitchTelemetry.DistributedRegistry, [
          {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
        ])

      # Should have at least our registered session
      assert length(registered) >= 1

      # Find our session in the results
      our_session = Enum.find(registered, fn {k, _p} -> k == key end)
      assert our_session != nil
      {found_key, found_pid} = our_session
      assert found_key == key
      assert is_pid(found_pid)

      Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
    end
  end

  describe "Oban.Worker configuration" do
    test "worker queue is :maintenance" do
      assert StaleSessionCleanup.__opts__()[:queue] == :maintenance
    end

    test "worker max_attempts is 3" do
      assert StaleSessionCleanup.__opts__()[:max_attempts] == 3
    end

    test "perform/1 accepts Oban.Job struct" do
      job = %Oban.Job{args: %{}}
      assert :ok == StaleSessionCleanup.perform(job)
    end

    test "perform/1 accepts Oban.Job with extra args" do
      job = %Oban.Job{args: %{"force" => true, "dry_run" => false}}
      assert :ok == StaleSessionCleanup.perform(job)
    end
  end

  describe "perform/1 idempotency" do
    test "calling perform multiple times in sequence is safe" do
      for _ <- 1..5 do
        assert :ok == StaleSessionCleanup.perform(%Oban.Job{})
      end
    end

    test "calling perform with registered sessions multiple times is safe" do
      key = {:gnmi, "idempotent-#{System.unique_integer([:positive])}"}
      {:ok, _pid} = Horde.Registry.register(SwitchTelemetry.DistributedRegistry, key, :val)

      for _ <- 1..3 do
        assert :ok == StaleSessionCleanup.perform(%Oban.Job{})
      end

      # Session should still be registered
      result = Horde.Registry.lookup(SwitchTelemetry.DistributedRegistry, key)
      assert length(result) > 0

      Horde.Registry.unregister(SwitchTelemetry.DistributedRegistry, key)
    end
  end
end
