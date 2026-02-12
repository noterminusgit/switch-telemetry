#!/usr/bin/env bash
# Deploys Flux downsampling tasks to InfluxDB v2.
# Usage: ./deploy_tasks.sh [INFLUXDB_HOST] [INFLUXDB_TOKEN] [INFLUXDB_ORG]
set -euo pipefail

HOST="${1:-http://localhost:8086}"
TOKEN="${2:-${INFLUXDB_TOKEN:-dev-token}}"
ORG="${3:-${INFLUXDB_ORG:-switch-telemetry}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Deploying Flux tasks to ${HOST} for org '${ORG}'..."

for task_file in "${SCRIPT_DIR}/tasks/"*.flux; do
  task_name="$(basename "${task_file}" .flux)"
  echo "  Creating task '${task_name}' from ${task_file}..."

  influx task create \
    --host "${HOST}" \
    --token "${TOKEN}" \
    --org "${ORG}" \
    --file "${task_file}" \
    2>/dev/null || echo "  Task '${task_name}' may already exist, skipping."
done

echo "Flux task deployment complete."
