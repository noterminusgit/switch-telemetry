defmodule SwitchTelemetry.AuthorizationTest do
  use ExUnit.Case, async: true

  alias SwitchTelemetry.Authorization
  alias SwitchTelemetry.Accounts.User
  alias SwitchTelemetry.Dashboards.Dashboard

  @admin %User{id: "admin-1", role: :admin}
  @operator %User{id: "operator-1", role: :operator}
  @viewer %User{id: "viewer-1", role: :viewer}

  @own_dashboard %Dashboard{id: "dash-1", created_by: "operator-1", is_public: false}
  @other_dashboard %Dashboard{id: "dash-2", created_by: "other-user", is_public: false}
  @public_dashboard %Dashboard{id: "dash-3", created_by: "other-user", is_public: true}

  # ── Admin tests ──────────────────────────────────────────────────────

  describe "admin role" do
    test "can do anything with any resource" do
      assert Authorization.can?(@admin, :view, :device)
      assert Authorization.can?(@admin, :create, :device)
      assert Authorization.can?(@admin, :edit, :device)
      assert Authorization.can?(@admin, :delete, :device)
      assert Authorization.can?(@admin, :view, :dashboard_list)
      assert Authorization.can?(@admin, :create, :dashboard)
      assert Authorization.can?(@admin, :edit, @own_dashboard)
      assert Authorization.can?(@admin, :edit, @other_dashboard)
      assert Authorization.can?(@admin, :delete, @own_dashboard)
      assert Authorization.can?(@admin, :delete, @other_dashboard)
      assert Authorization.can?(@admin, :view, @public_dashboard)
      assert Authorization.can?(@admin, :view, @other_dashboard)
      assert Authorization.can?(@admin, :create, :alert_rule)
      assert Authorization.can?(@admin, :edit, :alert_rule)
      assert Authorization.can?(@admin, :view, :alert)
      assert Authorization.can?(@admin, :manage, :users)
    end
  end

  # ── Operator tests ──────────────────────────────────────────────────

  describe "operator role" do
    test "can view any resource" do
      assert Authorization.can?(@operator, :view, :device)
      assert Authorization.can?(@operator, :view, :alert)
      assert Authorization.can?(@operator, :view, :dashboard_list)
      assert Authorization.can?(@operator, :view, @own_dashboard)
      assert Authorization.can?(@operator, :view, @other_dashboard)
      assert Authorization.can?(@operator, :view, @public_dashboard)
    end

    test "can create and edit devices" do
      assert Authorization.can?(@operator, :create, :device)
      assert Authorization.can?(@operator, :edit, :device)
    end

    test "can create and edit alert rules" do
      assert Authorization.can?(@operator, :create, :alert_rule)
      assert Authorization.can?(@operator, :edit, :alert_rule)
    end

    test "can create dashboards" do
      assert Authorization.can?(@operator, :create, :dashboard)
    end

    test "can edit own dashboards" do
      assert Authorization.can?(@operator, :edit, @own_dashboard)
    end

    test "cannot edit other users' dashboards" do
      refute Authorization.can?(@operator, :edit, @other_dashboard)
    end

    test "can delete own dashboards" do
      assert Authorization.can?(@operator, :delete, @own_dashboard)
    end

    test "cannot delete other users' dashboards" do
      refute Authorization.can?(@operator, :delete, @other_dashboard)
    end

    test "cannot delete devices" do
      refute Authorization.can?(@operator, :delete, :device)
    end

    test "cannot manage users" do
      refute Authorization.can?(@operator, :manage, :users)
    end

    test "cannot edit/delete dashboard when user id is nil" do
      operator_nil_id = %User{id: nil, role: :operator}
      dashboard_nil_creator = %Dashboard{id: "d", created_by: nil, is_public: false}

      refute Authorization.can?(operator_nil_id, :edit, dashboard_nil_creator)
      refute Authorization.can?(operator_nil_id, :delete, dashboard_nil_creator)
    end
  end

  # ── Viewer tests ─────────────────────────────────────────────────────

  describe "viewer role" do
    test "can view public dashboards" do
      assert Authorization.can?(@viewer, :view, @public_dashboard)
    end

    test "can view own dashboards (even if private)" do
      own_private = %Dashboard{id: "dash-own", created_by: "viewer-1", is_public: false}
      assert Authorization.can?(@viewer, :view, own_private)
    end

    test "cannot view other users' private dashboards" do
      refute Authorization.can?(@viewer, :view, @other_dashboard)
    end

    test "can view devices" do
      assert Authorization.can?(@viewer, :view, :device)
    end

    test "can view alerts" do
      assert Authorization.can?(@viewer, :view, :alert)
    end

    test "can view dashboard list" do
      assert Authorization.can?(@viewer, :view, :dashboard_list)
    end

    test "cannot create devices" do
      refute Authorization.can?(@viewer, :create, :device)
    end

    test "cannot edit devices" do
      refute Authorization.can?(@viewer, :edit, :device)
    end

    test "cannot delete devices" do
      refute Authorization.can?(@viewer, :delete, :device)
    end

    test "cannot create dashboards" do
      refute Authorization.can?(@viewer, :create, :dashboard)
    end

    test "cannot edit dashboards" do
      refute Authorization.can?(@viewer, :edit, @public_dashboard)
    end

    test "cannot delete dashboards" do
      refute Authorization.can?(@viewer, :delete, @public_dashboard)
    end

    test "cannot create alert rules" do
      refute Authorization.can?(@viewer, :create, :alert_rule)
    end

    test "cannot edit alert rules" do
      refute Authorization.can?(@viewer, :edit, :alert_rule)
    end

    test "cannot manage users" do
      refute Authorization.can?(@viewer, :manage, :users)
    end

    test "cannot view private dashboard when viewer id is nil" do
      viewer_nil_id = %User{id: nil, role: :viewer}
      dashboard_nil_creator = %Dashboard{id: "d", created_by: nil, is_public: false}

      refute Authorization.can?(viewer_nil_id, :view, dashboard_nil_creator)
    end
  end

  # ── Default deny tests ───────────────────────────────────────────────

  describe "default deny" do
    test "nil user is denied" do
      refute Authorization.can?(nil, :view, :device)
    end

    test "unknown role is denied" do
      unknown = %User{id: "u", role: :viewer}
      refute Authorization.can?(unknown, :teleport, :device)
    end
  end
end
