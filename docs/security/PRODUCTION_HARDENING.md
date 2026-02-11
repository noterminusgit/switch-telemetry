# Production Hardening Guide

## Transport Security

### HTTPS
- `force_ssl` is enabled in production config with HSTS
- SSL termination is expected at a reverse proxy (Nginx, HAProxy, AWS ALB)
- The app listens on HTTP internally; `rewrite_on: [:x_forwarded_proto]` handles proxy detection
- HSTS header is sent with all responses (max-age defaults to 31536000 seconds / 1 year)

### Content Security Policy
A strict CSP is configured in the router:
- `default-src 'self'` -- only load resources from same origin
- `script-src 'self' 'unsafe-eval'` -- VegaLite/Vega runtime requires `eval()` for spec compilation
- `style-src 'self' 'unsafe-inline'` -- Tailwind CSS and LiveView styles
- `img-src 'self' data: blob:` -- Vega chart rendering
- `connect-src 'self' wss: ws:` -- LiveView WebSocket
- `frame-ancestors 'none'` -- prevents clickjacking

**Trade-off**: `unsafe-eval` is required by Vega's runtime compiler. This is an accepted risk documented in ADR-003. Vega specs are generated server-side and pushed to the client; no user-generated specs are evaluated.

### Cookies
- Session cookie: `HttpOnly`, `SameSite=Lax`, `Secure` (via force_ssl)
- Remember-me cookie: signed, `HttpOnly`, `SameSite=Lax`, `Secure` (via force_ssl)

## Encryption at Rest

### Credentials
Device credentials (password, SSH key, TLS cert/key) are encrypted using Cloak Ecto with AES-256-GCM.
- Encryption key: `CLOAK_KEY` environment variable (32 bytes, base64-encoded)
- Key rotation: Deploy with new key, then run re-encryption migration

### Database
- Use PostgreSQL disk encryption (dm-crypt/LUKS or cloud provider encryption)
- Enable SSL for database connections in production

## Authentication

- Session-based authentication using Phoenix's signed cookies
- Passwords hashed with bcrypt (Elixir `bcrypt_elixir`)
- Minimum password length: 12 characters
- Session tokens: 32 bytes of cryptographic randomness
- Session validity: 60 days
- Password reset tokens: 1-day expiry

## Authorization

Three roles: `admin`, `operator`, `viewer`. See the permissions matrix in `docs/design/phase-6-auth.md`.

## Network Security

### BEAM Clustering
- Erlang distribution uses a shared cookie (`RELEASE_COOKIE`)
- **Firewall requirements**:
  - Port 4369/tcp (EPMD -- Erlang Port Mapper Daemon)
  - Ephemeral port range for distribution (configure with `inet_dist_listen_min/max` in `vm.args`)
  - These ports must ONLY be accessible between cluster nodes
- **libcluster** uses DNS-based discovery -- ensure DNS is trusted

### NETCONF (SSH)
- Connects to devices on port 830 via Erlang `:ssh`
- **Known limitation**: Host key verification is currently set to `silently_accept_hosts: true`
- **Mitigation**: NETCONF connections should only traverse trusted management networks
- **Future**: Implement known_hosts file or certificate-based host verification

### gNMI (gRPC)
- Connects to devices via gRPC (HTTP/2)
- TLS configuration depends on device setup
- Credentials are encrypted at rest (Cloak)

## Logging

### Sensitive Data Filtering
- Phoenix parameter filter configured for: `password`, `secret`, `token`, `ssh_key`, `tls_key`, `tls_cert`, `current_password`, `api_key`, `cloak_key`
- Credential schema has `@derive {Inspect, except: [...]}` to redact secrets from `inspect()` output
- User schema has `redact: true` on password fields

### Error Pages
- Production error pages return generic messages only (no stack traces)
- `ErrorHTML` and `ErrorJSON` use `Phoenix.Controller.status_message_from_template/1`

## Dependency Management

- Run `mix hex.audit` periodically to check for known vulnerabilities
- Run `npm audit` in `assets/` for JavaScript dependencies
- Keep dependencies updated with `mix hex.outdated`

## Secrets Management

- All secrets loaded from environment variables in `config/runtime.exs`
- Required secrets raise on missing (fail-fast)
- Development config uses placeholder values (never use in production)
- See `docs/security/ENV_VARS.md` for the complete variable reference
