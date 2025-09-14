#!/bin/bash
# JStack Cron Job Setup Script
# Location: scripts/core/setup_cron_jobs.sh
# Sets up automated SSL renewal and backups

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSTACK_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

setup_ssl_renewal_cron() {
  log "Setting up SSL certificate renewal cron job..."
  
  # Create cron job for SSL renewal (daily at 2 AM)
  CRON_SSL="0 2 * * * /usr/bin/certbot renew --quiet && cd $JSTACK_ROOT && docker-compose restart nginx"
  
  # Check if cron job already exists
  if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "$CRON_SSL") | crontab -
    log "SSL renewal cron job added"
  else
    log "SSL renewal cron job already exists"
  fi
}

setup_backup_cron() {
  log "Setting up automated backup cron jobs..."
  
  # Daily backup at 3 AM
  CRON_DAILY="0 3 * * * cd $JSTACK_ROOT && bash scripts/core/backup_restore.sh backup --full"
  
  # Weekly cleanup (keep last 7 daily backups)
  CRON_CLEANUP="0 4 * * 0 find $JSTACK_ROOT/backups -name 'jstack_full_*.tar.gz' -mtime +7 -delete"
  
  # Check if backup cron jobs already exist
  if ! crontab -l 2>/dev/null | grep -q "backup_restore.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_DAILY") | crontab -
    log "Daily backup cron job added"
  else
    log "Daily backup cron job already exists"
  fi
  
  if ! crontab -l 2>/dev/null | grep -q "jstack_full_.*tar.gz.*delete"; then
    (crontab -l 2>/dev/null; echo "$CRON_CLEANUP") | crontab -
    log "Backup cleanup cron job added"
  else
    log "Backup cleanup cron job already exists"
  fi
}

create_backup_dir() {
  mkdir -p "$JSTACK_ROOT/backups"
  mkdir -p "$JSTACK_ROOT/logs"
  log "Backup directories created"
}

remove_cron_jobs() {
  log "Removing JStack cron jobs..."
  crontab -l 2>/dev/null | grep -v "certbot renew" | grep -v "backup_restore.sh" | grep -v "jstack_full_.*tar.gz.*delete" | crontab -
  log "JStack cron jobs removed"
}

usage() {
  echo "Usage: $0 [install|remove|status]"
  echo "  install  - Set up SSL renewal and backup cron jobs"
  echo "  remove   - Remove all JStack cron jobs"
  echo "  status   - Show current JStack cron jobs"
  exit 1
}

show_status() {
  log "Current JStack cron jobs:"
  crontab -l 2>/dev/null | grep -E "(certbot|backup_restore|jstack_full)" || echo "No JStack cron jobs found"
}

main() {
  case "${1:-install}" in
    install)
      create_backup_dir
      setup_ssl_renewal_cron
      setup_backup_cron
      log "Cron jobs setup completed"
      show_status
      ;;
    remove)
      remove_cron_jobs
      ;;
    status)
      show_status
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"