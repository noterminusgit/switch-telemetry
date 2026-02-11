# Phase 6 Implementation Plan: Authentication & Authorization

## Wave 1: Foundation (sequential)
1. Add `bcrypt_elixir` dep, run `mix deps.get`
2. Create User schema (`lib/switch_telemetry/accounts/user.ex`)
3. Create UserToken schema (`lib/switch_telemetry/accounts/user_token.ex`)
4. Create migration: users + user_tokens tables
5. Create migration: add `created_by` to dashboards + alert_rules
6. Run migrations

## Wave 2: Core Logic (parallel agents)
7. Accounts context (`lib/switch_telemetry/accounts.ex`) - register, authenticate, sessions, tokens, password reset
8. UserNotifier (`lib/switch_telemetry/accounts/user_notifier.ex`) - email notifications
9. Authorization module (`lib/switch_telemetry/authorization.ex`) - role-based checks
10. Dashboard ownership - update Dashboard schema + Dashboards context for `created_by`

## Wave 3: Web Layer (parallel agents)
11. UserAuth module (`lib/switch_telemetry_web/user_auth.ex`) - plugs + LiveView on_mount
12. Controllers: UserSessionController, UserRegistrationController (admin-only), UserResetPasswordController
13. Controller HTML modules (login/register/reset forms)
14. Update router with auth pipelines
15. Update layouts (user menu, login/logout links)
16. UserLive.Settings (change email/password)
17. Admin UserLive.Index (manage users)

## Wave 4: Tests (parallel agents)
18. Update ConnCase with auth test helpers (`register_and_log_in_user`, `log_in_user`)
19. Auth controller tests
20. Authorization module tests
21. Update all existing LiveView tests to authenticate
22. LiveView auth tests (settings, admin)
