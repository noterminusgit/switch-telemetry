defmodule SwitchTelemetry.Collector.SubscriptionPathsTest do
  use ExUnit.Case, async: false

  alias SwitchTelemetry.Collector.SubscriptionPaths

  setup do
    # Use a tmp dir that mirrors the real priv/gnmi_paths structure,
    # copying the static JSON files so list_paths/1 works normally.
    tmp_dir =
      Path.join(System.tmp_dir!(), "gnmi_paths_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    src_dir = Application.app_dir(:switch_telemetry, "priv/gnmi_paths")

    # Copy all top-level JSON files (platform files + _common.json)
    src_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.each(fn file ->
      File.cp!(Path.join(src_dir, file), Path.join(tmp_dir, file))
    end)

    File.mkdir_p!(Path.join(tmp_dir, "device_overrides"))

    prev_env = Application.get_env(:switch_telemetry, :gnmi_paths_dir)
    Application.put_env(:switch_telemetry, :gnmi_paths_dir, tmp_dir)

    on_exit(fn ->
      if prev_env do
        Application.put_env(:switch_telemetry, :gnmi_paths_dir, prev_env)
      else
        Application.delete_env(:switch_telemetry, :gnmi_paths_dir)
      end

      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "list_paths/1" do
    test "returns common + IOS-XR paths for cisco_iosxr" do
      paths = SubscriptionPaths.list_paths(:cisco_iosxr)
      assert is_list(paths)
      assert length(paths) > 0

      # Should include common paths
      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings
      assert "/system/state/hostname" in path_strings

      # Should include IOS-XR specific paths
      assert Enum.any?(path_strings, &String.contains?(&1, "Cisco-IOS-XR"))
    end

    test "returns common + IOS-XE paths for cisco_iosxe" do
      paths = SubscriptionPaths.list_paths(:cisco_iosxe)
      assert is_list(paths)
      assert length(paths) > 0

      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings

      # Should include IOS-XE specific paths
      assert Enum.any?(path_strings, &String.contains?(&1, "Cisco-IOS-XE"))
    end

    test "returns common + JunOS paths for juniper_junos" do
      paths = SubscriptionPaths.list_paths(:juniper_junos)
      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings
      assert Enum.any?(path_strings, &String.contains?(&1, "junos"))
    end

    test "returns common + EOS paths for arista_eos" do
      paths = SubscriptionPaths.list_paths(:arista_eos)
      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings
      assert Enum.any?(path_strings, &String.contains?(&1, "Sysdb"))
    end

    test "returns common + NX-OS paths for cisco_nxos" do
      paths = SubscriptionPaths.list_paths(:cisco_nxos)
      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings
      assert Enum.any?(path_strings, &String.contains?(&1, "System"))
    end

    test "returns common + SR OS paths for nokia_sros" do
      paths = SubscriptionPaths.list_paths(:nokia_sros)
      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings
      assert Enum.any?(path_strings, &String.contains?(&1, "state/port"))
    end

    test "unknown platform returns only common paths" do
      paths = SubscriptionPaths.list_paths(:unknown_platform)
      assert is_list(paths)
      assert length(paths) > 0

      # Should have common paths
      path_strings = Enum.map(paths, & &1.path)
      assert "/interfaces/interface/state/counters" in path_strings
    end

    test "path entries have required fields" do
      paths = SubscriptionPaths.list_paths(:cisco_iosxr)

      for entry <- paths do
        assert is_binary(entry.path)
        assert is_binary(entry.description)
        assert is_binary(entry.category)
      end
    end

    test "paths are deduplicated" do
      paths = SubscriptionPaths.list_paths(:cisco_iosxr)
      path_strings = Enum.map(paths, & &1.path)
      assert length(path_strings) == length(Enum.uniq(path_strings))
    end
  end

  describe "list_paths/2 with device model override" do
    test "includes device override paths" do
      model = "test-model-#{System.unique_integer([:positive])}"

      override_paths = [
        %{path: "/custom/test/path", description: "Test override", category: "test"}
      ]

      :ok = SubscriptionPaths.save_device_override(model, override_paths)

      paths = SubscriptionPaths.list_paths(:cisco_iosxr, model)
      path_strings = Enum.map(paths, & &1.path)
      assert "/custom/test/path" in path_strings
    end

    test "nil device model returns same as list_paths/1" do
      paths_1 = SubscriptionPaths.list_paths(:cisco_iosxr)
      paths_2 = SubscriptionPaths.list_paths(:cisco_iosxr, nil)
      assert paths_1 == paths_2
    end
  end

  describe "save_device_override/2" do
    test "saves and subsequent list_paths includes them" do
      model = "test-save-#{System.unique_integer([:positive])}"

      paths = [
        %{path: "/test/saved/path", description: "Saved path", category: "test"}
      ]

      assert :ok = SubscriptionPaths.save_device_override(model, paths)

      loaded = SubscriptionPaths.list_paths(:cisco_iosxr, model)
      path_strings = Enum.map(loaded, & &1.path)
      assert "/test/saved/path" in path_strings
    end

    test "sanitizes model name for filename" do
      model = "Test/Model With Spaces!@#"

      paths = [
        %{path: "/test/sanitized", description: "Sanitized model", category: "test"}
      ]

      assert :ok = SubscriptionPaths.save_device_override(model, paths)
    end
  end
end
