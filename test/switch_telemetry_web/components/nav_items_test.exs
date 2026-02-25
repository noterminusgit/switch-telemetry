defmodule SwitchTelemetryWeb.Components.NavItemsTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetryWeb.Components.NavItems

  describe "items/0" do
    test "returns 6 standard navigation items" do
      items = NavItems.items()
      assert length(items) == 6
    end

    test "each item has path, icon, and label" do
      for item <- NavItems.items() do
        assert Map.has_key?(item, :path)
        assert Map.has_key?(item, :icon)
        assert Map.has_key?(item, :label)
        assert is_binary(item.path)
        assert String.starts_with?(item.icon, "hero-")
        assert is_binary(item.label)
      end
    end

    test "includes expected labels" do
      labels = Enum.map(NavItems.items(), & &1.label)
      assert "Dashboards" in labels
      assert "Devices" in labels
      assert "Alerts" in labels
      assert "Settings" in labels
    end
  end

  describe "admin_item/0" do
    test "returns users admin item" do
      item = NavItems.admin_item()
      assert item.label == "Users"
      assert item.icon == "hero-users"
      assert item.path =~ "/admin/users"
    end
  end
end
