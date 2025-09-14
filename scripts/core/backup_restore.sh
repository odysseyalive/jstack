#!/bin/bash
# JStack Backup & Restore Script
# Location: scripts/core/backup_restore.sh
# Supports: full/partial backup, restore, integrity check, Docker volumes/configs

set -e

JSTACK_CONFIG="$(dirname "$0")/../../jstack.config.default"
BACKUP_DIR="$(dirname "$0")/../../backups"
LOG_DIR="$(dirname "$0")/../../logs"
DOCKER_COMPOSE="$(dirname "$0")/../../docker-compose.yml"

usage() {
  echo "Usage: $0 [backup|restore|validate] [options]"
  echo "  backup   --full|--partial [service]"
  echo "  restore  <backup_file>"
  echo "  validate <backup_file>"
  exit 1
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/backup_restore.log"
}

backup_full() {
  TS=$(date '+%Y%m%d_%H%M%S')
  FILE="$BACKUP_DIR/jstack_full_$TS.tar.gz"
  log "Starting full backup to $FILE"
  tar czf "$FILE" \
    -C "$(dirname "$DOCKER_COMPOSE")" docker-compose.yml \
    -C "$(dirname "$JSTACK_CONFIG")" jstack.config.default \
    -C "$(dirname "$0")/../../data/supabase" . \
    -C "$(dirname "$0")/../../data/n8n" . \
    -C "$(dirname "$0")/../../data/chrome" . \
    -C "$(dirname "$0")/../../nginx/conf.d" . \
    -C "$(dirname "$0")/../../nginx/ssl" . \
     # Removed site-templates from backup
  log "Full backup completed: $FILE"
}

backup_partial() {
  SERVICE="$1"
  TS=$(date '+%Y%m%d_%H%M%S')
  FILE="$BACKUP_DIR/jstack_${SERVICE}_$TS.tar.gz"
  log "Starting partial backup for $SERVICE to $FILE"
  case "$SERVICE" in
    supabase)
      tar czf "$FILE" -C "$(dirname "$0")/../../data/supabase" .
      ;;
    n8n)
      tar czf "$FILE" -C "$(dirname "$0")/../../data/n8n" .
      ;;
    chrome)
      tar czf "$FILE" -C "$(dirname "$0")/../../data/chrome" .
      ;;
    nginx)
      tar czf "$FILE" -C "$(dirname "$0")/../../nginx/conf.d" . -C "$(dirname "$0")/../../nginx/ssl" .
      ;;
    site-templates)
      log "Partial backup for site-templates is not supported."
      ;;
    *)
      log "Unknown service: $SERVICE"
      ;;
  esac
  log "Partial backup for $SERVICE completed: $FILE"
}

restore_backup() {
  FILE="$1"
  log "Restoring from backup $FILE"
  tar xzf "$FILE" -C /
  log "Restore completed."
}

validate_backup() {
  FILE="$1"
  log "Validating backup $FILE"
  if tar tzf "$FILE" >/dev/null; then
    log "Backup $FILE integrity: OK"
  else
    log "Backup $FILE integrity: FAILED"
    exit 2
  fi
}

main() {
  if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup|restore> [options]" >&2
    exit 1
  fi
  CMD="$1"; shift
  case "$CMD" in
    backup)
      case "$1" in
        --full)
          backup_full
          ;;
        --partial)
          backup_partial "$2"
          ;;
        *)
          usage
          ;;
      esac
      ;;
    restore)
      restore_backup "$1"
      ;;
    validate)
      validate_backup "$1"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
