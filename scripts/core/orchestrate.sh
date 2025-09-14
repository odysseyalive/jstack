#!/bin/bash
# JStack Docker Compose Orchestration Script
# Usage: orchestrate.sh [up|down|restart|status] [service/template]

set -e

COMPOSE_FILE="$(dirname "$0")/../../docker-compose.yml"
## Removed SITE_TEMPLATES_DIR reference

usage() {
  echo "Usage: $0 [up|down|restart|status] [service/template]"
  exit 1
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

main() {
  if [ $# -eq 0 ]; then
    echo "Usage: $0 <action> [target]" >&2
    exit 1
  fi
  ACTION="$1"; shift
  TARGET="$1"
  case "$ACTION" in
    up)
  for DIR in "$(dirname "$0")/../../data/supabase" "$(dirname "$0")/../../data/n8n" "$(dirname "$0")/../../data/chrome" "$(dirname "$0")/../../nginx/conf.d" "$(dirname "$0")/../../nginx/ssl"; do
        if [ ! -d "$DIR" ]; then
          log "Creating missing directory: $DIR"
          mkdir -p "$DIR"
        fi
      done
      if [ -z "$TARGET" ]; then
        log "Starting all services via Docker Compose..."
        docker-compose -f "$COMPOSE_FILE" up -d
      else
        log "Starting $TARGET via Docker Compose..."
        docker-compose -f "$COMPOSE_FILE" up -d "$TARGET"
      fi
      ;;
    down)
      if [ -z "$TARGET" ]; then
        log "Stopping all services via Docker Compose..."
        docker-compose -f "$COMPOSE_FILE" down
      else
        log "Stopping $TARGET via Docker Compose..."
        docker-compose -f "$COMPOSE_FILE" stop "$TARGET"
      fi
      ;;
    restart)
      if [ -z "$TARGET" ]; then
        log "Restarting all services via Docker Compose..."
        docker-compose -f "$COMPOSE_FILE" restart
      else
        log "Restarting $TARGET via Docker Compose..."
        docker-compose -f "$COMPOSE_FILE" restart "$TARGET"
      fi
      ;;
    status)
      log "Showing status for all services via Docker Compose..."
      docker-compose -f "$COMPOSE_FILE" ps
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
