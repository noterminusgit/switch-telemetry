# Environment Variables Reference

All environment variables used by Switch Telemetry in production.

## Required

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection URL | `ecto://user:pass@host/switch_telemetry_prod` |
| `SECRET_KEY_BASE` | Phoenix signing secret (min 64 bytes). Generate with `mix phx.gen.secret` | `Abc123...` |
| `CLOAK_KEY` | AES-256-GCM encryption key (32 bytes, base64-encoded). Generate with `:crypto.strong_rand_bytes(32) \|> Base.encode64()` | `dVFyaWZS...` |
| `PHX_HOST` | Production hostname for URL generation | `telemetry.example.com` |

## Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | HTTP listen port | `4000` |
| `POOL_SIZE` | Database connection pool size | `20` (collector), `10` (web) |
| `ECTO_IPV6` | Enable IPv6 for database connections | unset (disabled) |
| `PHX_SERVER` | Start the Phoenix server (set to any value) | unset |
| `NODE_ROLE` | Node type: `collector`, `web`, or `both` | `both` |
| `RELEASE_NAME` | BEAM node basename for clustering | `switch_telemetry` |
| `CLUSTER_DNS` | DNS name for libcluster node discovery | `switch-telemetry.internal` |

## InfluxDB (Required)

| Variable | Description | Default |
|----------|-------------|---------|
| `INFLUXDB_HOST` | InfluxDB v2 host URL (including scheme) | `http://localhost` |
| `INFLUXDB_PORT` | InfluxDB v2 port | `8086` |
| `INFLUXDB_TOKEN` | InfluxDB admin/write token | (none -- required) |
| `INFLUXDB_ORG` | InfluxDB organization name | (none -- required) |
| `INFLUXDB_BUCKET` | InfluxDB raw metrics bucket name | `metrics_raw` |

## SMTP (Optional -- for email notifications)

| Variable | Description | Default |
|----------|-------------|---------|
| `SMTP_RELAY` | SMTP server hostname (enables email) | unset (disabled) |
| `SMTP_PORT` | SMTP server port | `587` |
| `SMTP_USERNAME` | SMTP authentication username | unset |
| `SMTP_PASSWORD` | SMTP authentication password | unset |

## BEAM Clustering

| Variable | Description | Default |
|----------|-------------|---------|
| `RELEASE_COOKIE` | Erlang distribution cookie (must match across all nodes) | auto-generated |
| `RELEASE_NODE` | Full node name (e.g., `web@10.0.0.1`) | auto from release |

## Security Notes

- **SECRET_KEY_BASE**: Rotate by generating a new value and restarting all nodes. Active sessions will be invalidated.
- **CLOAK_KEY**: Rotation requires re-encrypting all credential data. Keep the old key available during migration.
- **RELEASE_COOKIE**: Must be identical on all nodes in the cluster. Treat as a secret -- anyone with the cookie can connect to the BEAM.
- **SMTP_PASSWORD**: Transmitted to the SMTP relay over TLS (`tls: :always` is configured).
- Never commit any of these values to source control.
