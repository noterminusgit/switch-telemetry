# ADR-007: Session-Based Authentication with RBAC

**Status:** Accepted
**Date:** 2026-02-15
**Deciders:** Engineering team
**Context:** The platform needs user authentication and role-based access control for multi-user operation with sensitive infrastructure data

## Context

The platform needs user authentication and role-based access control for multi-user operation. Network telemetry dashboards contain sensitive infrastructure data -- device IP addresses, port configurations, traffic metrics, and alert rules that reveal network topology and operational status. Different users need different access levels:

- **Admins** manage the system: user accounts, admin email allowlists, device credentials, all resources
- **Operators** configure devices and alerts, create and manage their own dashboards
- **Viewers** only see public dashboards, their own dashboards, and read-only device/alert data

Without access control, any user with network access to the web interface could view or modify all telemetry data and device configurations.

## Decision

Implement session-based authentication with a `UserToken` database table, magic link passwordless login for admin onboarding, and 3-tier role-based access control (admin/operator/viewer). Use `Authorization.can?/3` for permission checks throughout the application.

## Alternatives Considered

### Alternative 1: JWT Tokens

**Pros:**
- Stateless: no server-side session storage needed
- Works well for API consumers and cross-service authentication
- Standard format with broad library support

**Cons:**
- No external API consumers currently; the only client is the LiveView browser UI
- Stateless tokens are harder to revoke (require a blocklist or short expiry + refresh tokens)
- Session-based is simpler for a LiveView app where the server already maintains socket state
- JWT adds complexity (signing keys, token refresh, expiry management) without benefit

**Why Rejected:** No external API consumers currently, stateless tokens are harder to revoke, session-based is simpler for a LiveView app.

### Alternative 2: OAuth 2.0 / OpenID Connect

**Pros:**
- Delegated authentication to an external identity provider
- Users can log in with existing corporate credentials
- Standardized protocol with mature libraries

**Cons:**
- No external identity provider requirement exists
- Adds significant complexity (authorization server, token exchange, callback URLs)
- External dependency on an IdP being available and configured
- Overkill for a self-hosted network telemetry platform

**Why Rejected:** No external identity provider requirement, adds unnecessary complexity and external dependencies.

### Alternative 3: API Keys Only

**Pros:**
- Simple to implement for programmatic access
- No session management needed

**Cons:**
- Not sufficient for interactive browser users (no login flow, no session management)
- No user identity for audit trails on dashboard/device changes
- Would still need a separate auth system for the web UI

**Why Noted:** Future consideration for programmatic access (e.g., external systems querying metrics APIs), but not sufficient as the primary authentication mechanism for interactive users.

## RBAC Model

The authorization model is defined in `lib/switch_telemetry/authorization.ex` using pattern matching on `%User{role: role}` structs. The `can?/3` function takes a user, an action (`:view | :create | :edit | :delete`), and a resource.

### Role Permissions

| Permission | Admin | Operator | Viewer |
|------------|-------|----------|--------|
| All actions on all resources | Yes | -- | -- |
| View any resource | -- | Yes | -- |
| Create/edit devices | -- | Yes | -- |
| Create/edit alert rules | -- | Yes | -- |
| Create dashboards | -- | Yes | -- |
| Edit/delete own dashboards | -- | Yes (ownership check) | -- |
| View public dashboards | -- | -- | Yes |
| View own dashboards | -- | -- | Yes (ownership check) |
| View devices (read-only) | -- | -- | Yes |
| View alerts (read-only) | -- | -- | Yes |
| View dashboard list | -- | -- | Yes |
| Everything else | -- | Denied | Denied |

### Ownership Checks

Operators can edit and delete dashboards they created. Viewers can view dashboards they created. Both use pattern matching on `%Dashboard{created_by: uid}` against `%User{id: uid}`:

```elixir
def can?(%User{role: :operator, id: uid}, :edit, %Dashboard{created_by: uid})
    when not is_nil(uid),
    do: true

def can?(%User{role: :viewer, id: uid}, :view, %Dashboard{created_by: uid})
    when not is_nil(uid),
    do: true
```

### Default Deny

Any permission not explicitly granted returns `false`:

```elixir
def can?(_user, _action, _resource), do: false
```

## Magic Link Login Flow

Magic links provide passwordless login for admin onboarding. The flow is implemented across `Accounts`, `UserSessionController`, and `UserNotifier`:

1. **User requests magic link**: User submits their email via `POST /users/magic_link`. The controller (`UserSessionController.create_magic_link/2`) checks if the email is on the admin allowlist via `Accounts.admin_email?/1`.

2. **Token generated**: If the email is allowed, `Accounts.get_or_create_user_for_magic_link/1` either finds the existing user or creates a new admin account with a generated password (via `Accounts.generate_password/0`). New accounts are auto-confirmed via `User.confirm_changeset/1`.

3. **Email sent**: `Accounts.deliver_magic_link_instructions/2` builds a hashed email token with context `"magic_link"` (via `UserToken.build_email_token/2`), stores it in the `user_tokens` table, and sends the link via `UserNotifier.deliver_magic_link/2`.

4. **Token verified**: When the user clicks the link (`GET /users/magic_link/:token`), `UserSessionController.magic_link_callback/2` calls `Accounts.verify_magic_link_token/1`, which verifies the token against the database and deletes all `"magic_link"` tokens for that user (single-use enforcement).

5. **Session created**: On successful verification, `UserAuth.log_in_user/2` generates a session token via `Accounts.generate_user_session_token/1`, stores it in the `user_tokens` table, renews the session ID (CSRF protection), and redirects to the signed-in path (`/dashboards`).

6. **Admin promotion**: `Accounts.maybe_promote_to_admin/1` checks the `admin_emails` table. If the user's email matches an allowlist entry, their role is updated to `:admin` via `Accounts.update_user_role/2`. Users already with `:admin` role are returned unchanged.

### Security Properties

- The same response is shown regardless of whether the email is on the allowlist (prevents email enumeration)
- Magic link tokens are single-use (all tokens for the user are deleted after verification)
- Tokens expire after 1 day (`@reset_password_validity_in_days` in `UserToken`)
- New accounts created via magic link receive a generated password via separate email (fallback login method)

## Session Management

Sessions are managed through the `UserToken` schema and `UserAuth` plug module:

- **Session tokens**: 32-byte random tokens stored as raw binary in the `user_tokens` table with context `"session"`
- **Token validity**: 60 days (`@session_validity_in_days` in `UserToken`)
- **Remember-me cookie**: Optional signed cookie (`_switch_telemetry_web_user_remember_me`) with 60-day max age, `http_only: true`, `same_site: "Lax"`
- **Session renewal**: On login, `renew_session/1` deletes the CSRF token and clears the session to prevent fixation attacks
- **LiveView integration**: `on_mount` hooks (`:mount_current_user`, `:ensure_authenticated`, `:ensure_admin`) load the user from the session token and enforce access on LiveView socket connections
- **Logout broadcast**: `log_out_user/1` broadcasts a `"disconnect"` message to the user's `live_socket_id`, terminating all connected LiveView sockets

### Plug Pipeline

| Plug Function | Purpose |
|---------------|---------|
| `fetch_current_user/2` | Loads user from session token or remember-me cookie, assigns `:current_user` |
| `redirect_if_user_is_authenticated/2` | Bounces authenticated users away from login/registration pages |
| `require_authenticated_user/2` | Redirects unauthenticated users to login, stores return path for GET requests |
| `require_admin/2` | Redirects non-admin users to root path with error flash |

## Encryption at Rest

Device credentials (passwords, SSH keys, TLS certificates/keys) are encrypted at rest using Cloak Vault with AES-256-GCM. The implementation consists of:

- `SwitchTelemetry.Vault` -- Cloak Vault module configured via `:switch_telemetry` app env
- `SwitchTelemetry.Encrypted.Binary` -- Cloak.Ecto.Binary type using the Vault for transparent encryption/decryption
- `SwitchTelemetry.Devices.Credential` -- Uses `Encrypted.Binary` type for `password`, `ssh_key`, `tls_cert`, and `tls_key` fields

Sensitive fields are excluded from `Inspect` output via `@derive {Inspect, except: [:password, :ssh_key, :tls_key]}`.

## Consequences

### Positive
1. Simple implementation with no external auth dependencies -- everything runs in the same BEAM cluster
2. Magic links enable easy admin onboarding without password management overhead
3. Admin email allowlist (`admin_emails` table) provides controlled privilege escalation with database-backed audit trail
4. `Authorization.can?/3` with pattern matching is easy to read, extend, and test
5. Session-based approach works naturally with Phoenix LiveView's socket authentication via `on_mount` hooks
6. Cloak Vault encryption protects device credentials at rest (AES-256-GCM)
7. Anti-enumeration protections on login and magic link endpoints

### Negative
1. Session tokens require database lookups on every request (via `fetch_current_user/2`)
2. Magic link flow requires a working email delivery system (Swoosh/UserNotifier)
3. No federated identity support (users must be created locally)
4. Admin email allowlist is a simple mechanism; no support for group-based or attribute-based access control

### Mitigations
- Session token lookups are simple indexed queries on the `user_tokens` table (fast)
- Swoosh supports multiple adapters including a local mailbox adapter for development
- Federated identity (OAuth/OIDC) can be added later without changing the RBAC model
- Easy to extend with API keys later for programmatic access (add a new token context)

## Related ADRs
- ADR-005: InfluxDB Migration (established the Backend behaviour pattern used for testability)
- ADR-006: Behaviour Abstractions for Protocol Testability (same Mox testing pattern)

## Review Schedule
**Last Reviewed:** 2026-02-15
**Next Review:** 2026-08-15
