defmodule SwitchTelemetry.Authorization do
  @moduledoc "Simple role-based authorization."

  alias SwitchTelemetry.Accounts.User
  alias SwitchTelemetry.Dashboards.Dashboard

  # Admin can do everything
  def can?(%User{role: :admin}, _action, _resource), do: true

  # Operator permissions
  def can?(%User{role: :operator}, :view, _resource), do: true
  def can?(%User{role: :operator}, :create, :device), do: true
  def can?(%User{role: :operator}, :edit, :device), do: true
  def can?(%User{role: :operator}, :create, :alert_rule), do: true
  def can?(%User{role: :operator}, :edit, :alert_rule), do: true
  def can?(%User{role: :operator}, :create, :dashboard), do: true

  def can?(%User{role: :operator, id: uid}, :edit, %Dashboard{created_by: uid})
      when not is_nil(uid),
      do: true

  def can?(%User{role: :operator, id: uid}, :delete, %Dashboard{created_by: uid})
      when not is_nil(uid),
      do: true

  # Viewer permissions
  def can?(%User{role: :viewer}, :view, %Dashboard{is_public: true}), do: true

  def can?(%User{role: :viewer, id: uid}, :view, %Dashboard{created_by: uid})
      when not is_nil(uid),
      do: true

  def can?(%User{role: :viewer}, :view, :device), do: true
  def can?(%User{role: :viewer}, :view, :alert), do: true
  def can?(%User{role: :viewer}, :view, :dashboard_list), do: true

  # Default deny
  def can?(_user, _action, _resource), do: false
end
