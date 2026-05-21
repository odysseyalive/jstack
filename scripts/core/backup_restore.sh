#!/bin/bash
# JStack Backup & Restore Script
# Location: scripts/core/backup_restore.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="$REPO_ROOT/backups"
LOG_DIR="$REPO_ROOT/logs"
DOCKER_COMPOSE="$REPO_ROOT/docker-compose.yml"
JSTACK_CONFIG="$REPO_ROOT/jstack.config.default"

usage() {
  echo "Usage: $0 [backup|restore|validate] [options]"
  echo "  backup   --full | --partial nginx | --partial site:<domain>"
  echo "  restore  <backup_file>"
  echo "  validate <backup_file>"
  exit 1
}

log() {
  mkdir -p "$LOG_DIR"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/backup_restore.log"
}

backup_full() {
  TS=$(date '+%Y%m%d_%H%M%S')
  FILE="$BACKUP_DIR/jstack_full_$TS.tar.gz"
  mkdir -p "$BACKUP_DIR"
  log "Starting full backup to $FILE"
  tar czf "$FILE" \
    -C "$REPO_ROOT" docker-compose.yml \
    -C "$REPO_ROOT" jstack.config.default \
    -C "$REPO_ROOT/nginx/conf.d" . \
    -C "$REPO_ROOT/nginx/certbot/conf" . \
    -C "$REPO_ROOT" sites
  log "Full backup completed: $FILE"
}

backup_partial() {
  TARGET="$1"
  TS=$(date '+%Y%m%d_%H%M%S')
  mkdir -p "$BACKUP_DIR"
  case "$TARGET" in
    nginx)
      FILE="$BACKUP_DIR/jstack_nginx_$TS.tar.gz"
      log "Starting partial backup for nginx to $FILE"
      tar czf "$FILE" \
        -C "$REPO_ROOT/nginx/conf.d" . \
        -C "$REPO_ROOT/nginx/certbot/conf" .
      log "Partial backup for nginx completed: $FILE"
      ;;
    site:*)
      DOMAIN="${TARGET#site:}"
      SITE_DIR="$REPO_ROOT/sites/$DOMAIN"
      if [ ! -d "$SITE_DIR" ]; then
        log "Site $DOMAIN not found at $SITE_DIR"
        exit 2
      fi
      FILE="$BACKUP_DIR/jstack_site_${DOMAIN}_$TS.tar.gz"
      log "Starting partial backup for site $DOMAIN to $FILE"
      tar czf "$FILE" -C "$SITE_DIR" .
      log "Partial backup for site $DOMAIN completed: $FILE"
      ;;
    *)
      log "Unknown partial target: $TARGET"
      usage
      ;;
  esac
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
    usage
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
