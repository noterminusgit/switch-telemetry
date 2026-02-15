defmodule SwitchTelemetry.AuthorizationPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SwitchTelemetry.Authorization
  alias SwitchTelemetry.Accounts.User

  # ---------------------------------------------------------------
  # Generators — use the valid sets from the source code
  # ---------------------------------------------------------------

  # Actions defined in the Authorization module's @type
  @actions [:view, :create, :edit, :delete]

  # Atom resources that appear in the source
  @atom_resources [:device, :alert, :alert_rule, :dashboard, :dashboard_list, :users]

  defp action_gen do
    member_of(@actions)
  end

  defp atom_resource_gen do
    member_of(@atom_resources)
  end

  # ---------------------------------------------------------------
  # Admin — can do everything
  # ---------------------------------------------------------------
  describe "admin can?/3 property" do
    property "returns true for all action/atom-resource combinations" do
      admin = %User{id: "admin-prop-1", role: :admin}

      check all(
              action <- action_gen(),
              resource <- atom_resource_gen()
            ) do
        assert Authorization.can?(admin, action, resource) == true
      end
    end

    property "returns true even for non-standard actions" do
      admin = %User{id: "admin-prop-2", role: :admin}

      check all(action <- member_of([:view, :create, :edit, :delete, :manage, :teleport, :nuke])) do
        assert Authorization.can?(admin, action, :device) == true
      end
    end
  end

  # ---------------------------------------------------------------
  # Viewer — denied for create, edit, delete on all atom resources
  # ---------------------------------------------------------------
  describe "viewer can?/3 property" do
    property "returns false for :create on all atom resources" do
      viewer = %User{id: "viewer-prop-1", role: :viewer}

      check all(resource <- atom_resource_gen()) do
        refute Authorization.can?(viewer, :create, resource)
      end
    end

    property "returns false for :edit on all atom resources" do
      viewer = %User{id: "viewer-prop-2", role: :viewer}

      check all(resource <- atom_resource_gen()) do
        refute Authorization.can?(viewer, :edit, resource)
      end
    end

    property "returns false for :delete on all atom resources" do
      viewer = %User{id: "viewer-prop-3", role: :viewer}

      check all(resource <- atom_resource_gen()) do
        refute Authorization.can?(viewer, :delete, resource)
      end
    end
  end

  # ---------------------------------------------------------------
  # nil user — always denied
  # ---------------------------------------------------------------
  describe "nil user can?/3 property" do
    property "nil user always returns false for any action and resource" do
      check all(
              action <- action_gen(),
              resource <- atom_resource_gen()
            ) do
        refute Authorization.can?(nil, action, resource)
      end
    end
  end
end
