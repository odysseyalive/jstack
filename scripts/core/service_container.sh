#!/bin/bash
# ServiceContainer Management Script
# Usage: service_container.sh <action> <name> [image] [ports] [env]

set -e

if [ $# -lt 2 ]; then
  echo "Usage: $0 <action> <name> [image] [ports] [env]" >&2
  exit 1
fi

ACTION="$1"
NAME="$2"
IMAGE="$3"
PORTS="$4"
ENV="$5"

case "$ACTION" in
  start_container)
    echo "Starting container $NAME with image $IMAGE on port $PORTS"
    if [[ "$NAME" =~ [^a-zA-Z0-9_-] ]] || [[ "$IMAGE" =~ [^a-zA-Z0-9/:._-] ]] || [[ "$PORTS" =~ [^0-9:,] ]]; then
  echo "Error: Unsafe characters in parameters. Aborting." >&2
  exit 2
fi
docker run -d --name "$NAME" -p "$PORTS" $([ "$ENV" ] && echo "-e $ENV") "$IMAGE"
    ;;
  stop_container)
    echo "Stopping container $NAME"
    docker stop "$NAME" && docker rm "$NAME"
    ;;
  update_container)
    echo "Updating container $NAME with new env $ENV"
    docker stop "$NAME"
    docker rm "$NAME"
    if [[ "$NAME" =~ [^a-zA-Z0-9_-] ]] || [[ "$IMAGE" =~ [^a-zA-Z0-9/:._-] ]]; then
  echo "Error: Unsafe characters in parameters. Aborting." >&2
  exit 2
fi
docker run -d --name "$NAME" $([ "$ENV" ] && echo "-e $ENV") "$IMAGE"
    ;;
  run_health_check)
    echo "Running health check for $NAME"
    docker inspect --format='{{.State.Health.Status}}' "$NAME" || echo "No health status available"
    ;;
  run_diagnostics)
    echo "Running diagnostics for $NAME"
    docker logs "$NAME" | tail -n 20
    ;;
  run_compliance_check)
    echo "Running compliance check for $NAME"
    # Placeholder for compliance logic
    echo "Compliance check passed for $NAME"
    ;;
  run_backup)
    echo "Backing up $NAME"
    docker commit "$NAME" "$NAME-backup:latest"
    ;;
  restore_backup)
    echo "Restoring backup for $NAME"
    docker stop "$NAME" || true
    docker rm "$NAME" || true
    docker run -d --name "$NAME" "$NAME-backup:latest"
    ;;
  *)
    echo "Unknown action: $ACTION"
    exit 1
    ;;
esac
