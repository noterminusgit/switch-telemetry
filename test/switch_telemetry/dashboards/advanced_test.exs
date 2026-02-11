defmodule SwitchTelemetry.Dashboards.AdvancedTest do
  use SwitchTelemetry.DataCase, async: true

  alias SwitchTelemetry.Dashboards
  alias SwitchTelemetry.Dashboards.Dashboard

  describe "clone_dashboard/2" do
    test "clones dashboard with new ID" do
      {:ok, original} =
        Dashboards.create_dashboard(%{
          id: "dash_orig",
          name: "Original",
          description: "Test desc",
          layout: :grid,
          refresh_interval_ms: 10_000
        })

      {:ok, clone} = Dashboards.clone_dashboard(original)
      assert clone.id != original.id
      assert clone.name == "Copy of Original"
      assert clone.description == "Test desc"
      assert clone.layout == :grid
      assert clone.refresh_interval_ms == 10_000
      assert clone.is_public == false
    end

    test "clones widgets with new IDs" do
      {:ok, original} =
        Dashboards.create_dashboard(%{id: "dash_clone_w", name: "With Widgets"})

      {:ok, _w1} =
        Dashboards.add_widget(original, %{
          id: "wgt_orig1",
          title: "CPU",
          chart_type: :line,
          queries: [%{"device_id" => "dev1", "path" => "/cpu"}]
        })

      {:ok, _w2} =
        Dashboards.add_widget(original, %{
          id: "wgt_orig2",
          title: "Memory",
          chart_type: :area
        })

      original = Dashboards.get_dashboard!(original.id)
      {:ok, clone} = Dashboards.clone_dashboard(original)

      assert length(clone.widgets) == 2
      clone_ids = Enum.map(clone.widgets, & &1.id)
      refute "wgt_orig1" in clone_ids
      refute "wgt_orig2" in clone_ids

      cpu_widget = Enum.find(clone.widgets, &(&1.title == "CPU"))
      assert cpu_widget.chart_type == :line
      assert cpu_widget.queries == [%{"device_id" => "dev1", "path" => "/cpu"}]
    end

    test "sets created_by when provided" do
      {:ok, user} =
        SwitchTelemetry.Accounts.register_user(%{
          email: "clone_test@example.com",
          password: "valid_password123"
        })

      {:ok, original} =
        Dashboards.create_dashboard(%{id: "dash_clone_user", name: "User Clone"})

      {:ok, clone} = Dashboards.clone_dashboard(original, user.id)
      assert clone.created_by == user.id
    end
  end

  describe "change_dashboard/2" do
    test "returns changeset" do
      dashboard = %Dashboard{id: "dash_cs", name: "Test"}
      changeset = Dashboards.change_dashboard(dashboard, %{name: "Updated"})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "dashboard tags" do
    test "creates dashboard with tags" do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{
          id: "dash_tags",
          name: "Tagged",
          tags: ["network", "core"]
        })

      assert dashboard.tags == ["network", "core"]
    end

    test "updates dashboard tags" do
      {:ok, dashboard} =
        Dashboards.create_dashboard(%{id: "dash_tags2", name: "Tag Update"})

      {:ok, updated} = Dashboards.update_dashboard(dashboard, %{tags: ["new_tag"]})
      assert updated.tags == ["new_tag"]
    end
  end

  describe "list_device_options/0" do
    test "returns empty list when no devices" do
      assert Dashboards.list_device_options() == []
    end
  end
end
