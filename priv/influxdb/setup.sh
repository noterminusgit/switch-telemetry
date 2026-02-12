#!/usr/bin/env bash
# Creates InfluxDB v2 buckets with retention policies for Switch Telemetry.
# Usage: ./setup.sh [INFLUXDB_HOST] [INFLUXDB_TOKEN] [INFLUXDB_ORG]
set -euo pipefail

HOST="${1:-http://localhost:8086}"
TOKEN="${2:-${INFLUXDB_TOKEN:-dev-token}}"
ORG="${3:-${INFLUXDB_ORG:-switch-telemetry}}"

echo "Setting up InfluxDB buckets at ${HOST} for org '${ORG}'..."

# metrics_raw: 30 days retention
influx bucket create \
  --host "${HOST}" \
  --token "${TOKEN}" \
  --org "${ORG}" \
  --name metrics_raw \
  --retention 720h \
  2>/dev/null || echo "Bucket 'metrics_raw' already exists"

# metrics_5m: 180 days retention
influx bucket create \
  --host "${HOST}" \
  --token "${TOKEN}" \
  --org "${ORG}" \
  --name metrics_5m \
  --retention 4320h \
  2>/dev/null || echo "Bucket 'metrics_5m' already exists"

# metrics_1h: 730 days retention (~2 years)
influx bucket create \
  --host "${HOST}" \
  --token "${TOKEN}" \
  --org "${ORG}" \
  --name metrics_1h \
  --retention 17520h \
  2>/dev/null || echo "Bucket 'metrics_1h' already exists"

# metrics_test: no retention (for tests)
influx bucket create \
  --host "${HOST}" \
  --token "${TOKEN}" \
  --org "${ORG}" \
  --name metrics_test \
  --retention 0 \
  2>/dev/null || echo "Bucket 'metrics_test' already exists"

echo "InfluxDB bucket setup complete."
