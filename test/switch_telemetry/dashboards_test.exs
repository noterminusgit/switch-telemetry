defmodule SwitchTelemetry.DashboardsTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetry.Devices.Device
  alias SwitchTelemetry.Collector.Subscription

  defp valid_dashboard_attrs(overrides \\ %{}) do
    id = "dash_#{System.unique_integer([:positive])}"

    Map.merge(
      %{id: id, name: "Dashboard #{id}"},
      overrides
    )
  end

  defp create_device(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    defaults = %{
      id: "dev_#{unique}",
      hostname: "router-#{unique}.example.com",
      ip_address: "10.0.0.#{rem(unique, 254) + 1}",
      platform: :cisco_iosxr,
      transport: :gnmi
    }

    %Device{}
    |> Device.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp create_subscription(device, attrs) do
    unique = System.unique_integer([:positive])

    defaults = %{
      id: "sub_#{unique}",
      device_id: device.id,
      paths: ["/interfaces/interface/state/counters"],
      enabled: true
    }

    %Subscription{}
    |> Subscription.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "list_dashboards/0" do
    test "returns empty list when no dashboards" do
      assert Dashboards.list_dashboards() == []
    end

    test "returns all dashboards" do
      {:ok, _} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, _} = Dashboards.create_dashboard(valid_dashboard_attrs())
      assert length(Dashboards.list_dashboards()) == 2
    end
  end

  describe "get_dashboard!/1" do
    test "returns dashboard with preloaded widgets" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      dashboard = Dashboards.get_dashboard!(d.id)
      assert dashboard.id == d.id
      assert dashboard.widgets == []
    end

    test "preloads widgets when present" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, _} = Dashboards.add_widget(d, %{id: "wgt_preload1", title: "W1", chart_type: :line})
      {:ok, _} = Dashboards.add_widget(d, %{id: "wgt_preload2", title: "W2", chart_type: :bar})

      dashboard = Dashboards.get_dashboard!(d.id)
      assert length(dashboard.widgets) == 2
    end

    test "raises for missing dashboard" do
      assert_raise Ecto.NoResultsError, fn ->
        Dashboards.get_dashboard!("nonexistent")
      end
    end
  end

  describe "create_dashboard/1" do
    test "creates with valid attrs" do
      assert {:ok, d} =
               Dashboards.create_dashboard(valid_dashboard_attrs(%{name: "My Dashboard"}))

      assert d.name == "My Dashboard"
      assert d.layout == :grid
    end

    test "applies default values" do
      assert {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      assert d.layout == :grid
      assert d.refresh_interval_ms == 5_000
      assert d.is_public == false
      assert d.tags == []
    end

    test "creates with optional fields" do
      attrs =
        valid_dashboard_attrs(%{
          description: "A test dashboard",
          layout: :freeform,
          refresh_interval_ms: 10_000,
          is_public: true,
          tags: ["network", "core"]
        })

      assert {:ok, d} = Dashboards.create_dashboard(attrs)
      assert d.description == "A test dashboard"
      assert d.layout == :freeform
      assert d.refresh_interval_ms == 10_000
      assert d.is_public == true
      assert d.tags == ["network", "core"]
    end

    test "rejects missing id" do
      assert {:error, changeset} = Dashboards.create_dashboard(%{name: "No ID"})
      assert errors_on(changeset).id
    end

    test "rejects missing name" do
      assert {:error, changeset} = Dashboards.create_dashboard(%{id: "dash_x"})
      assert errors_on(changeset).name
    end

    test "rejects duplicate name" do
      attrs = valid_dashboard_attrs(%{name: "Unique Name"})
      {:ok, _} = Dashboards.create_dashboard(attrs)

      assert {:error, changeset} =
               Dashboards.create_dashboard(valid_dashboard_attrs(%{name: "Unique Name"}))

      assert errors_on(changeset).name
    end

    test "enforces name max length" do
      long_name = String.duplicate("a", 256)
      attrs = valid_dashboard_attrs(%{name: long_name})
      assert {:error, changeset} = Dashboards.create_dashboard(attrs)
      assert errors_on(changeset).name
    end

    test "enforces description max length" do
      long_desc = String.duplicate("a", 1001)
      attrs = valid_dashboard_attrs(%{name: "Valid Name", description: long_desc})
      assert {:error, changeset} = Dashboards.create_dashboard(attrs)
      assert errors_on(changeset).description
    end
  end

  describe "update_dashboard/2" do
    test "updates name" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      assert {:ok, updated} = Dashboards.update_dashboard(d, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
    end

    test "updates multiple fields" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())

      assert {:ok, updated} =
               Dashboards.update_dashboard(d, %{
                 name: "Updated",
                 description: "New desc",
                 layout: :freeform,
                 refresh_interval_ms: 15_000
               })

      assert updated.name == "Updated"
      assert updated.description == "New desc"
      assert updated.layout == :freeform
      assert updated.refresh_interval_ms == 15_000
    end

    test "rejects invalid updates" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      long_name = String.duplicate("x", 256)
      assert {:error, changeset} = Dashboards.update_dashboard(d, %{name: long_name})
      assert errors_on(changeset).name
    end
  end

  describe "delete_dashboard/1" do
    test "deletes dashboard" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      assert {:ok, _} = Dashboards.delete_dashboard(d)

      assert_raise Ecto.NoResultsError, fn ->
        Dashboards.get_dashboard!(d.id)
      end
    end

    test "deletes dashboard with widgets" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_cascade1", title: "Gone", chart_type: :line})
      assert {:ok, _} = Dashboards.delete_dashboard(d)

      assert_raise Ecto.NoResultsError, fn ->
        Dashboards.get_widget!(w.id)
      end
    end
  end

  describe "add_widget/2" do
    test "adds widget to dashboard" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())

      assert {:ok, widget} =
               Dashboards.add_widget(d, %{id: "wgt_test1", title: "CPU", chart_type: :line})

      assert widget.title == "CPU"
      assert widget.chart_type == :line
      assert widget.dashboard_id == d.id
    end

    test "adds widget with all chart types" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())

      for {chart_type, idx} <- Enum.with_index([:line, :bar, :area, :points, :gauge, :table]) do
        assert {:ok, widget} =
                 Dashboards.add_widget(d, %{
                   id: "wgt_type_#{idx}",
                   title: "Chart #{idx}",
                   chart_type: chart_type
                 })

        assert widget.chart_type == chart_type
      end
    end

    test "adds widget with optional fields" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())

      assert {:ok, widget} =
               Dashboards.add_widget(d, %{
                 id: "wgt_opts",
                 title: "Full Widget",
                 chart_type: :line,
                 position: %{x: 0, y: 0, w: 12, h: 6},
                 time_range: %{type: "relative", duration: "24h"},
                 queries: [%{"device_id" => "dev1", "path" => "/interfaces"}]
               })

      assert widget.position == %{x: 0, y: 0, w: 12, h: 6}
      assert widget.queries == [%{"device_id" => "dev1", "path" => "/interfaces"}]
    end

    test "adds widget with string keys" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())

      assert {:ok, widget} =
               Dashboards.add_widget(d, %{
                 "id" => "wgt_str1",
                 "title" => "String Keys",
                 "chart_type" => "line"
               })

      assert widget.title == "String Keys"
      assert widget.dashboard_id == d.id
    end

    test "rejects widget without required fields" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      assert {:error, changeset} = Dashboards.add_widget(d, %{id: "wgt_bad"})
      errors = errors_on(changeset)
      assert errors.title
      assert errors.chart_type
    end
  end

  describe "update_widget/2" do
    test "updates widget title" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_upd1", title: "Old", chart_type: :line})
      assert {:ok, updated} = Dashboards.update_widget(w, %{title: "New"})
      assert updated.title == "New"
    end

    test "updates widget chart_type" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_upd2", title: "Type", chart_type: :line})
      assert {:ok, updated} = Dashboards.update_widget(w, %{chart_type: :bar})
      assert updated.chart_type == :bar
    end

    test "updates widget queries" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_upd3", title: "Queries", chart_type: :line})

      new_queries = [%{"device_id" => "dev1", "path" => "/cpu"}]
      assert {:ok, updated} = Dashboards.update_widget(w, %{queries: new_queries})
      assert updated.queries == new_queries
    end
  end

  describe "delete_widget/1" do
    test "deletes widget" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_del1", title: "Gone", chart_type: :bar})
      assert {:ok, _} = Dashboards.delete_widget(w)

      assert_raise Ecto.NoResultsError, fn ->
        Dashboards.get_widget!(w.id)
      end
    end
  end

  describe "get_widget!/1" do
    test "returns widget by id" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_get1", title: "Get Me", chart_type: :area})
      found = Dashboards.get_widget!(w.id)
      assert found.id == w.id
      assert found.title == "Get Me"
    end

    test "raises for missing widget" do
      assert_raise Ecto.NoResultsError, fn ->
        Dashboards.get_widget!("nonexistent")
      end
    end
  end

  describe "change_dashboard/2" do
    test "returns changeset for existing dashboard" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      changeset = Dashboards.change_dashboard(d, %{name: "Changed"})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset with no changes" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      changeset = Dashboards.change_dashboard(d)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "change_widget/2" do
    test "returns changeset for existing widget" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_cs1", title: "CS", chart_type: :line})
      changeset = Dashboards.change_widget(w, %{title: "Changed"})
      assert %Ecto.Changeset{} = changeset
    end

    test "returns changeset with no changes" do
      {:ok, d} = Dashboards.create_dashboard(valid_dashboard_attrs())
      {:ok, w} = Dashboards.add_widget(d, %{id: "wgt_cs2", title: "CS2", chart_type: :bar})
      changeset = Dashboards.change_widget(w)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "list_devices_for_widget_picker/0" do
    test "returns empty list when no devices exist" do
      assert Dashboards.list_devices_for_widget_picker() == []
    end

    test "returns devices grouped by platform" do
      create_device(%{hostname: "xr-router-1.example.com", platform: :cisco_iosxr})
      create_device(%{hostname: "xr-router-2.example.com", platform: :cisco_iosxr})
      create_device(%{hostname: "junos-sw-1.example.com", platform: :juniper_junos})

      result = Dashboards.list_devices_for_widget_picker()

      assert length(result) == 2

      {xr_label, xr_devices} = Enum.find(result, fn {label, _} -> label == "Cisco IOS-XR" end)
      assert xr_label == "Cisco IOS-XR"
      assert length(xr_devices) == 2

      {junos_label, junos_devices} =
        Enum.find(result, fn {label, _} -> label == "Juniper Junos" end)

      assert junos_label == "Juniper Junos"
      assert length(junos_devices) == 1
    end

    test "sorts groups alphabetically by platform label" do
      create_device(%{hostname: "junos-1.example.com", platform: :juniper_junos})
      create_device(%{hostname: "arista-1.example.com", platform: :arista_eos})
      create_device(%{hostname: "xr-1.example.com", platform: :cisco_iosxr})

      result = Dashboards.list_devices_for_widget_picker()
      labels = Enum.map(result, &elem(&1, 0))
      assert labels == ["Arista EOS", "Cisco IOS-XR", "Juniper Junos"]
    end

    test "returns {hostname, id} tuples within each group" do
      device = create_device(%{hostname: "test-router.example.com", platform: :cisco_iosxr})

      [{_label, devices}] = Dashboards.list_devices_for_widget_picker()
      assert [{hostname, id}] = devices
      assert hostname == "test-router.example.com"
      assert id == device.id
    end
  end

  describe "list_paths_for_device/1" do
    test "returns empty list for nonexistent device" do
      assert Dashboards.list_paths_for_device("nonexistent") == []
    end

    test "returns empty list when device has no subscriptions" do
      device = create_device()
      assert Dashboards.list_paths_for_device(device.id) == []
    end

    test "returns paths grouped by category from enabled subscriptions" do
      device = create_device(%{platform: :cisco_iosxr})

      create_subscription(device, %{
        paths: [
          "/interfaces/interface/state/counters",
          "/system/state/hostname"
        ]
      })

      result = Dashboards.list_paths_for_device(device.id)

      assert length(result) >= 1

      # Each entry should be {category_label, [{path, path}]}
      for {label, paths} <- result do
        assert is_binary(label)
        assert is_list(paths)

        for {display, value} <- paths do
          assert is_binary(display)
          assert is_binary(value)
          assert display == value
        end
      end
    end

    test "excludes paths from disabled subscriptions" do
      device = create_device(%{platform: :cisco_iosxr})

      create_subscription(device, %{
        paths: ["/interfaces/interface/state/counters"],
        enabled: true
      })

      create_subscription(device, %{
        paths: ["/system/state/hostname"],
        enabled: false
      })

      result = Dashboards.list_paths_for_device(device.id)
      all_paths = Enum.flat_map(result, fn {_cat, paths} -> Enum.map(paths, &elem(&1, 1)) end)

      assert "/interfaces/interface/state/counters" in all_paths
      refute "/system/state/hostname" in all_paths
    end

    test "groups unknown paths under Other" do
      device = create_device(%{platform: :cisco_iosxr})

      create_subscription(device, %{
        paths: ["/custom/vendor/specific/path"]
      })

      result = Dashboards.list_paths_for_device(device.id)
      {label, paths} = Enum.find(result, fn {l, _} -> l == "Other" end)
      assert label == "Other"
      assert {"/custom/vendor/specific/path", "/custom/vendor/specific/path"} in paths
    end

    test "sorts groups alphabetically" do
      device = create_device(%{platform: :cisco_iosxr})

      create_subscription(device, %{
        paths: [
          "/system/state/hostname",
          "/interfaces/interface/state/counters",
          "/components/component/state"
        ]
      })

      result = Dashboards.list_paths_for_device(device.id)
      labels = Enum.map(result, &elem(&1, 0))
      assert labels == Enum.sort(labels)
    end
  end
end
