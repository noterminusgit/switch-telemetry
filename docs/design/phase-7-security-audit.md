# Phase 7 Design: Security Audit

## Overview

Comprehensive security review and hardening of the entire codebase. This phase produces no new features — it hardens what exists. Each audit area results in concrete fixes committed to the codebase and a checklist documenting what was verified.

## Audit Areas

### 1. Credential Encryption (Cloak)

**Status**: `cloak_ecto` is a dependency but may not be fully wired up.

**Audit**:
- [ ] Verify `Cloak.Vault` is configured and started in supervision tree
- [ ] Verify device credentials (username, password, SSH keys) are encrypted at rest
- [ ] Verify encryption key rotation mechanism exists
- [ ] Verify decrypted credentials never appear in logs or error messages
- [ ] Verify `Credential` schema uses `Cloak.Ecto.Encrypted.Binary` field types
- [ ] Add `config :switch_telemetry, SwitchTelemetry.Vault` with key from env var

**Fixes to implement**:
- Configure Cloak Vault GenServer in supervision tree
- Migrate credential fields to encrypted types if not already done
- Add key derivation from `CLOAK_KEY` environment variable
- Add `Inspect` protocol implementation for Credential to redact sensitive fields

### 2. Input Validation & Injection

**Audit**:
- [ ] Review all Ecto changesets for proper validation
- [ ] Review raw SQL queries in `Metrics.Queries` for injection vectors
- [ ] Review `time_bucket` interval parameter allowlist (already done — verify completeness)
- [ ] Review any `String.to_atom/1` calls (DoS vector via atom table exhaustion)
- [ ] Review `SweetXml` xpath expressions for XML injection
- [ ] Review `Jason.decode/1` calls for unexpected input handling
- [ ] Review device IP address validation (must be valid IPv4/IPv6)
- [ ] Review LiveView event handlers for parameter tampering

**Fixes to implement**:
- Add IP address format validation to Device changeset
- Add hostname format validation (RFC 1123)
- Ensure all user-facing string inputs have length limits
- Verify no `String.to_atom/1` on user input (use `String.to_existing_atom/1` or avoid)

### 3. Authentication Hardening (Phase 6 follow-up)

**Audit**:
- [ ] Verify bcrypt work factor is adequate (default 12 is fine)
- [ ] Verify session tokens are properly invalidated on logout
- [ ] Verify password reset tokens expire
- [ ] Verify email confirmation tokens expire
- [ ] Verify brute force protection (rate limiting login attempts)
- [ ] Verify CSRF tokens on all state-changing requests
- [ ] Verify LiveView socket authentication (on_mount hooks)
- [ ] Verify API endpoints (if any) have proper auth

**Fixes to implement**:
- Add rate limiting to login endpoint (Plug-based, using ETS counter or Hammer)
- Add account lockout after N failed attempts
- Add password complexity requirements (min length, no common passwords)
- Add session timeout (configurable, default 24h)

### 4. Transport Security

**Audit**:
- [ ] Verify Phoenix endpoint force_ssl config for production
- [ ] Verify Secure, HttpOnly, SameSite cookie attributes
- [ ] Verify HSTS header configuration
- [ ] Verify gRPC connections to devices use TLS (or document when not)
- [ ] Verify SSH connections to devices validate host keys (or document policy)
- [ ] Verify webhook notifications use HTTPS
- [ ] Verify Finch connection pool TLS configuration

**Fixes to implement**:
- Enable `force_ssl` in production endpoint config
- Set `secure: true` on session cookie in production
- Add `Strict-Transport-Security` header via Plug
- Add TLS certificate verification for outbound Finch requests
- Document device connection security model (TLS for gNMI, SSH for NETCONF)

### 5. Content Security Policy

**Audit**:
- [ ] Review current CSP headers (if any)
- [ ] VegaLite/Vega requires `unsafe-eval` for spec compilation — document this trade-off
- [ ] Review for inline scripts/styles that need CSP nonces
- [ ] Review third-party resource loading

**Fixes to implement**:
- Add CSP header via Plug with policy:
  - `default-src 'self'`
  - `script-src 'self' 'unsafe-eval'` (required for Vega runtime)
  - `style-src 'self' 'unsafe-inline'` (Tailwind may need this)
  - `img-src 'self' data:` (Vega renders to canvas/SVG)
  - `connect-src 'self' wss:` (LiveView WebSocket)
- Document Vega `unsafe-eval` requirement and risk assessment

### 6. Secrets Management

**Audit**:
- [ ] Review all `System.get_env/1` calls for sensitive values
- [ ] Verify no secrets in `config/config.exs` or `config/dev.exs`
- [ ] Verify `.gitignore` excludes `.env`, `*.pem`, `*.key` files
- [ ] Verify `runtime.exs` is the only place secrets are read
- [ ] Verify signing salts are adequate length and not hardcoded test values
- [ ] Review endpoint secret_key_base source

**Fixes to implement**:
- Update `.gitignore` with comprehensive secret file patterns
- Verify/rotate endpoint signing salts (session, live_view)
- Document all required environment variables for production deployment
- Add `config :switch_telemetry, :secret_key_base` validation on boot

### 7. Dependency Audit

**Audit**:
- [ ] Run `mix deps.audit` (if hex_audit available) or `mix hex.audit`
- [ ] Review `mix.lock` for known vulnerable versions
- [ ] Check for outdated dependencies with `mix hex.outdated`
- [ ] Review `googleapis` Elixir version warning (non-blocking but track)
- [ ] Verify no unnecessary dependencies
- [ ] Review npm dependencies in `assets/package.json` for vulnerabilities

**Fixes to implement**:
- Update any dependencies with known CVEs
- Run `npm audit` in assets/ and fix findings
- Document accepted risks for any unfixable warnings
- Add `mix hex.audit` to CI pipeline (documented, not implemented in this phase)

### 8. Logging & Observability Security

**Audit**:
- [ ] Verify no credentials, passwords, or tokens in log output
- [ ] Verify no PII in log output beyond what's necessary
- [ ] Review Logger metadata for sensitive fields
- [ ] Review error pages (ErrorHTML, ErrorJSON) don't leak stack traces in production
- [ ] Verify Oban job args don't contain secrets

**Fixes to implement**:
- Add `@derive {Inspect, except: [:password, :hashed_password, :token]}` to sensitive schemas
- Configure Logger to filter sensitive params: `config :phoenix, :filter_parameters`
- Verify `ErrorHTML` and `ErrorJSON` return generic messages in prod
- Add Oban job arg sanitization for notification channel configs

### 9. BEAM/OTP Security

**Audit**:
- [ ] Review Erlang distribution cookie configuration
- [ ] Verify BEAM ports are not exposed publicly (epmd 4369, distribution port range)
- [ ] Review Horde/libcluster node discovery — can unauthorized nodes join?
- [ ] Review Phoenix.PubSub message handling — can malformed messages crash handlers?
- [ ] Review GenServer `handle_info` clauses for unexpected messages

**Fixes to implement**:
- Document required firewall rules for BEAM clustering (4369/tcp + ephemeral range)
- Add cookie configuration via environment variable in `rel/env.sh.eex`
- Add catch-all `handle_info` clauses to all GenServers (log + ignore unexpected messages)
- Document libcluster security model and network isolation requirements

## Deliverables

1. **Security checklist** (`docs/security/AUDIT_CHECKLIST.md`) — completed checklist with pass/fail/fix for each item
2. **Code fixes** — all identified vulnerabilities fixed and committed
3. **Security documentation** (`docs/security/PRODUCTION_HARDENING.md`) — production deployment security guide
4. **Environment variables** (`docs/security/ENV_VARS.md`) — complete list of all env vars with descriptions and security notes
5. **Zero new features** — this phase is audit-only, no new functionality

## Testing Strategy

- Verify all existing tests still pass after hardening changes
- Add security-specific tests:
  - Login rate limiting test
  - CSRF protection test
  - Unauthorized access tests for each role
  - Credential redaction in logs test
  - CSP header presence test
- Run full test suite: `mix test`
- Verify zero warnings: `mix compile --warnings-as-errors`
