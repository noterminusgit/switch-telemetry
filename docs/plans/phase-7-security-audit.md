# Phase 7 Implementation Plan: Security Audit & Hardening

## Wave 1: Credential Encryption + Input Validation (parallel agents)

### Agent A: Cloak Vault + Credential Encryption
1. Create `lib/switch_telemetry/vault.ex` (Cloak.Vault module)
2. Create `lib/switch_telemetry/encrypted/binary.ex` (Cloak.Ecto.Encrypted.Binary type)
3. Add Vault to supervision tree in `application.ex`
4. Add Cloak config to `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/runtime.exs`
5. Create migration to change credential columns from `:text` to `:binary` (encrypted)
6. Update `Credential` schema to use encrypted field types
7. Add `@derive {Inspect, except: [...]}` to Credential schema
8. Test: credential round-trip (write encrypted, read decrypted)

### Agent B: Input Validation + XML Safety
1. Add IP address format validation to Device changeset (IPv4/IPv6 regex)
2. Add hostname format validation (RFC 1123) to Device changeset
3. Add port range validation (1-65535) to Device changeset
4. Add length limits to all string fields across schemas
5. Fix `String.to_atom/1` in queries.ex and query_router.ex → use `String.to_existing_atom/1`
6. Add path validation to Subscription schema (no XML special chars)
7. Escape filter_path in netconf_session.ex `build_get_rpc/2`
8. Test: validation tests for device, subscription

## Wave 2: Transport Security + Logging + Config (parallel agents)

### Agent C: Transport Security + CSP + Headers
1. Add `force_ssl` config to `config/runtime.exs` (behind `PHX_ENABLE_SSL` env var)
2. Add `secure: true` to session cookie in production
3. Add CSP header plug in endpoint.ex
4. Add HSTS header configuration
5. Document Vega `unsafe-eval` requirement
6. Add `secure: true` to remember-me cookie in production
7. Test: CSP header presence test

### Agent D: Logging Security + Secrets + Filter Params
1. Add `config :phoenix, :filter_parameters` to config.exs
2. Add `@derive {Inspect, except: [...]}` to User, UserToken schemas
3. Add Oban job arg sanitization for notification channels
4. Update `.gitignore` with `.env*`, `*.pem`, `*.key` patterns
5. Document NETCONF SSH host key policy (add comment to netconf_session.ex)
6. Create `docs/security/ENV_VARS.md` with all env vars
7. Create `docs/security/PRODUCTION_HARDENING.md`
8. Test: filter_parameters test

## Wave 3: Audit Docs + Final Tests (sequential)

### Agent E: Audit Checklist + Dependency Audit + Final
1. Run `mix hex.audit` and document findings
2. Run `npm audit` in assets/ and document findings
3. Create `docs/security/AUDIT_CHECKLIST.md` with pass/fail/fix for each item
4. Run full test suite, fix any failures
5. Verify zero warnings
