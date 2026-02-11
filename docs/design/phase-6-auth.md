# Phase 6 Design: Authentication & Authorization

## Overview

Add user accounts with session-based authentication (Phoenix standard `phx.gen.auth` pattern) and role-based authorization. Three roles control access: admin, operator, viewer. Dashboards become user-owned. Device management and alert configuration require elevated privileges.

## Domain Model

### User

```elixir
%User{
  id: "usr_...",
  email: "ops@example.com",
  hashed_password: "...",
  role: :operator,               # :admin | :operator | :viewer
  confirmed_at: ~U[...],
  inserted_at: ~U[...],
  updated_at: ~U[...]
}
```

### UserToken

Standard `phx.gen.auth` token table for sessions and email confirmation.

```elixir
%UserToken{
  id: auto_increment,
  user_id: "usr_...",
  token: <<binary>>,
  context: "session",            # "session" | "confirm" | "reset_password"
  sent_to: "ops@example.com",
  inserted_at: ~U[...]
}
```

## Roles & Permissions Matrix

| Action | Admin | Operator | Viewer |
|--------|-------|----------|--------|
| View dashboards | Yes | Yes | Yes (public only unless owner) |
| Create/edit dashboards | Yes | Yes (own) | No |
| Delete dashboards | Yes | Own only | No |
| View devices | Yes | Yes | Yes |
| Create/edit devices | Yes | Yes | No |
| Delete devices | Yes | No | No |
| Manage credentials | Yes | No | No |
| View alerts | Yes | Yes | Yes |
| Create/edit alert rules | Yes | Yes | No |
| Manage notification channels | Yes | No | No |
| Manage users | Yes | No | No |

## Architecture

### Authentication (phx.gen.auth pattern)

- Session-based auth using Phoenix's built-in signed cookies
- `Accounts` context with `register_user/1`, `authenticate_user/2`, `get_user_by_session_token/1`
- Plug pipeline: `fetch_current_user` assigns `current_user` to conn/socket
- LiveView `on_mount` hook for authenticated LiveViews
- Login/register/forgot-password pages

### Authorization

Simple role-checking module — no external library needed:

```elixir
defmodule SwitchTelemetry.Authorization do
  def can?(%User{role: :admin}, _action, _resource), do: true

  def can?(%User{role: :operator}, :create, :device), do: true
  def can?(%User{role: :operator}, :edit, :device), do: true
  def can?(%User{role: :operator}, :create, :alert_rule), do: true
  def can?(%User{role: :operator}, :edit, :alert_rule), do: true
  def can?(%User{role: :operator}, :create, :dashboard), do: true
  def can?(%User{role: :operator}, :edit, %Dashboard{created_by: uid}), do: ...
  def can?(%User{role: :operator}, :delete, %Dashboard{created_by: uid}), do: ...

  def can?(%User{role: :viewer}, :view, _resource), do: true
  def can?(%User{role: :viewer}, :view, %Dashboard{is_public: true}), do: true

  def can?(_user, _action, _resource), do: false
end
```

### Dashboard Ownership

- Add `created_by` field to `dashboards` table (FK to users)
- Existing dashboards get assigned to first admin user (migration)
- `is_public` flag already exists — viewers can only see public dashboards or those they own

### Schema Changes

- `dashboards` table: add `created_by` column (string FK to users, nullable during migration)
- `alert_rules` table: add `created_by` column (string FK to users)

## Dependencies

```elixir
# New deps
{:bcrypt_elixir, "~> 3.0"},   # Password hashing (phx.gen.auth standard)
```

Swoosh already added in Phase 5 for email confirmation/password reset.

## Module Structure

```
lib/switch_telemetry/
  accounts/
    user.ex                     # Ecto schema
    user_token.ex               # Ecto schema
    user_notifier.ex            # Email notifications (confirm, reset)
  accounts.ex                   # Context: register, login, confirm, reset
  authorization.ex              # Role-based permission checks

lib/switch_telemetry_web/
  controllers/
    user_session_controller.ex  # Login/logout
    user_registration_controller.ex  # Register
    user_confirmation_controller.ex  # Email confirm
    user_reset_password_controller.ex  # Password reset
  live/
    user_live/
      index.ex                  # Admin: list/manage users
      settings.ex               # User: change email/password
  user_auth.ex                  # Plugs: fetch_current_user, require_authenticated_user, require_role
```

## Router Changes

```elixir
# Unauthenticated routes
scope "/", SwitchTelemetryWeb do
  pipe_through [:browser, :redirect_if_user_is_authenticated]
  get "/users/register", UserRegistrationController, :new
  post "/users/register", UserRegistrationController, :create
  get "/users/log_in", UserSessionController, :new
  post "/users/log_in", UserSessionController, :create
  get "/users/reset_password", UserResetPasswordController, :new
  # ...
end

# Authenticated routes (all existing routes move here)
scope "/", SwitchTelemetryWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/", DashboardLive.Index, :index   # redirect home to dashboards
  live "/dashboards", DashboardLive.Index, :index
  # ... all existing LiveView routes ...
  live "/alerts", AlertLive.Index, :index
  # ...
end

# Admin-only routes
scope "/admin", SwitchTelemetryWeb do
  pipe_through [:browser, :require_authenticated_user, :require_admin]
  live "/users", UserLive.Index, :index
end
```

## Seeding

- First user created via `mix run priv/repo/seeds.exs` is `:admin`
- Or: `mix switch_telemetry.create_admin` Mix task for bootstrapping

## Testing Strategy

- Adapt from `phx.gen.auth` test patterns
- Test role-based access: each role can/cannot access appropriate routes
- Test dashboard ownership: operator sees own + public, admin sees all
- Test LiveView mount rejects unauthenticated/unauthorized users
- Update all existing LiveView tests to authenticate first
