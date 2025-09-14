#!/bin/bash
# Diagnostics and Health Checks Script
# Usage: diagnostics.sh <service_name>

set -e
SERVICE="$1"

if [ -z "$SERVICE" ]; then
  echo "No service name provided."
  exit 1
fi

echo "Running diagnostics for $SERVICE..."

docker inspect "$SERVICE" || echo "Docker inspect failed for $SERVICE"
docker logs "$SERVICE" | tail -n 20 || echo "No logs available for $SERVICE"

echo "Checking health status for $SERVICE..."
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$SERVICE" 2>/dev/null || echo "unknown")
echo "Health status: $HEALTH_STATUS"

echo "Diagnostics and health checks completed for $SERVICE."
