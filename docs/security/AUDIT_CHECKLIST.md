# Security Audit Checklist

Completed: 2026-02-11 | Phase 7 Security Audit

## 1. Credential Encryption (Cloak)

| Item | Status | Notes |
|------|--------|-------|
| Cloak.Vault configured and started | FIXED | Created `SwitchTelemetry.Vault`, added to supervision tree |
| Device credentials encrypted at rest | FIXED | `password`, `ssh_key`, `tls_cert`, `tls_key` use `SwitchTelemetry.Encrypted.Binary` (AES-256-GCM) |
| Encryption key from env var | FIXED | `CLOAK_KEY` in `runtime.exs`, raises if missing in prod |
| Credential inspect redaction | FIXED | `@derive {Inspect, except: [:password, :ssh_key, :tls_key]}` on Credential schema |
| Migration for binary columns | FIXED | Migration 20240101000017 converts text to binary |
| Round-trip test | PASS | `vault_test.exs` verifies encrypt/decrypt cycle |
| Raw storage test | PASS | Confirms DB stores ciphertext, not plaintext |

## 2. Input Validation & Injection

| Item | Status | Notes |
|------|--------|-------|
| IP address format validation | FIXED | `:inet.parse_address/1` validates IPv4/IPv6 in Device changeset |
| Hostname format validation | FIXED | RFC 1123 regex + max 253 chars in Device changeset |
| Port range validation | FIXED | `validate_inclusion(:gnmi_port, 1..65535)` and `:netconf_port` |
| `String.to_atom/1` usage | FIXED | Replaced with explicit allowlist `safe_column_to_atom/1` in queries.ex and query_router.ex |
| Subscription path validation | FIXED | Rejects XML special chars, max 512 chars, must match `/[a-zA-Z0-9/_\-\.:]+` |
| time_bucket SQL injection | PASS | Already protected by `@valid_bucket_sizes` allowlist guard |
| table name SQL injection | PASS | Already protected by `when table in ["metrics_5m", "metrics_1h"]` guard |
| String length limits | FIXED | Added to Credential, AlertRule, NotificationChannel, Dashboard schemas |
| Device validation tests | PASS | 17 tests for IP, hostname, port validation |
| Subscription validation tests | PASS | 8 tests for path validation |
| Schema length limit tests | PASS | 11 tests across schemas |

## 3. Authentication Hardening

| Item | Status | Notes |
|------|--------|-------|
| Bcrypt work factor | PASS | Default factor 12 (adequate for current hardware) |
| Session token invalidation on logout | PASS | `delete_user_session_token/1` removes from DB |
| Password reset token expiry | PASS | 1-day expiry in `UserToken.verify_email_token_query/2` |
| Email confirmation token expiry | PASS | 1-day expiry (same mechanism) |
| Session token expiry | PASS | 60-day validity in `verify_session_token_query/1` |
| CSRF protection | PASS | `:protect_from_forgery` plug in browser pipeline |
| LiveView socket auth | PASS | `on_mount: :ensure_authenticated` in `live_session` |
| Admin LiveView auth | PASS | `on_mount: :ensure_admin` + `require_admin` plug |
| Rate limiting login | DEFERRED | Recommended for future: add Hammer or ETS-based rate limiting |
| Account lockout | DEFERRED | Recommended for future: lock after N failed attempts |

## 4. Transport Security

| Item | Status | Notes |
|------|--------|-------|
| force_ssl in production | FIXED | `force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]` |
| HSTS header | FIXED | Enabled via force_ssl |
| Session cookie HttpOnly | FIXED | Explicit `http_only: true` in endpoint session options |
| Session cookie SameSite | PASS | Already set to `Lax` |
| Session cookie Secure | FIXED | Handled by `force_ssl` / `Plug.SSL` in production |
| Remember-me cookie HttpOnly | FIXED | Added `http_only: true` to UserAuth options |
| Remember-me cookie signed | PASS | Already `sign: true` |
| gRPC TLS | N/A | TLS depends on device configuration; credentials encrypted at rest |
| SSH host keys | DOCUMENTED | `silently_accept_hosts: true` is a known limitation; documented in hardening guide |
| Webhook HTTPS | PASS | Finch with `tls: :always` for SMTP; webhook URLs are user-configured |

## 5. Content Security Policy

| Item | Status | Notes |
|------|--------|-------|
| CSP header configured | FIXED | Via `put_secure_browser_headers` in router |
| `default-src 'self'` | PASS | Only same-origin resources |
| `script-src 'self' 'unsafe-eval'` | PASS | `unsafe-eval` required for Vega runtime |
| `style-src 'self' 'unsafe-inline'` | PASS | Required for Tailwind/LiveView |
| `img-src 'self' data: blob:` | PASS | Required for Vega SVG/canvas |
| `connect-src 'self' wss: ws:` | PASS | Required for LiveView WebSocket |
| `frame-ancestors 'none'` | PASS | Prevents clickjacking |
| CSP test | PASS | `headers_test.exs` verifies presence and directives |
| Vega unsafe-eval documented | PASS | Documented in PRODUCTION_HARDENING.md |

## 6. Secrets Management

| Item | Status | Notes |
|------|--------|-------|
| No secrets in config.exs | PASS | Only default/dev values |
| runtime.exs is the secrets source | PASS | All prod secrets from env vars |
| .gitignore excludes secrets | FIXED | Added `.env*`, `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`, `secrets/` |
| SECRET_KEY_BASE validated | PASS | Raises if missing in prod |
| CLOAK_KEY validated | FIXED | Raises if missing in prod |
| Signing salts adequate | PASS | 8-char salts (session + live_view) are Phoenix defaults |
| ENV_VARS.md documented | FIXED | Complete reference at `docs/security/ENV_VARS.md` |

## 7. Dependency Audit

| Item | Status | Notes |
|------|--------|-------|
| `mix hex.audit` | PASS | No retired packages found |
| `npm audit` | PASS | 0 vulnerabilities |
| `googleapis` warning | DOCUMENTED | Non-blocking warning about Elixir ~> 1.18 requirement |
| Unused dependencies | PASS | `cloak_ecto` now properly used |

## 8. Logging & Observability Security

| Item | Status | Notes |
|------|--------|-------|
| filter_parameters configured | FIXED | 10 sensitive parameter names filtered from Phoenix logs |
| Credential inspect redaction | FIXED | `@derive {Inspect, except: [...]}` on Credential |
| User password redaction | PASS | `redact: true` on password fields (Ecto built-in) |
| UserToken inspect redaction | FIXED | `@derive {Inspect, except: [:token]}` |
| Error pages generic | PASS | ErrorHTML/ErrorJSON return status messages only |
| Oban job args | PASS | Notification workers use channel IDs, not credentials |

## 9. BEAM/OTP Security

| Item | Status | Notes |
|------|--------|-------|
| Distribution cookie | DOCUMENTED | `RELEASE_COOKIE` env var; documented in ENV_VARS.md |
| EPMD port exposure | DOCUMENTED | Firewall rules documented in PRODUCTION_HARDENING.md |
| GenServer catch-all handlers | PASS | All 8 GenServers have `handle_info(_msg, state)` catch-all |
| Horde/libcluster security | DOCUMENTED | Network isolation requirements in PRODUCTION_HARDENING.md |
| PubSub message handling | PASS | LiveView handlers use pattern matching, unknown messages ignored |

## Summary

| Category | Fixed | Pass | Deferred | Documented |
|----------|-------|------|----------|------------|
| Credential Encryption | 5 | 2 | 0 | 0 |
| Input Validation | 6 | 5 | 0 | 0 |
| Authentication | 0 | 8 | 2 | 0 |
| Transport Security | 4 | 4 | 0 | 2 |
| Content Security Policy | 1 | 6 | 0 | 1 |
| Secrets Management | 3 | 4 | 0 | 0 |
| Dependencies | 0 | 3 | 0 | 1 |
| Logging | 3 | 3 | 0 | 0 |
| BEAM/OTP | 0 | 2 | 0 | 3 |
| **Total** | **22** | **37** | **2** | **7** |

**Deferred items** (recommended for future sprints):
1. Login rate limiting (Hammer or ETS-based throttle)
2. Account lockout after failed attempts
