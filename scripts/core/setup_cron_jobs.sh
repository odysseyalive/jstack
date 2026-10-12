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
  CRON_SSL="0 2 * * * /usr/bin/certbot renew --quiet && cd \"$JSTACK_ROOT\" && docker compose restart nginx"
  
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
  
  # Daily backup at 3 AM, as the user that owns jstack (never root: the root-owned
  # certbot tree and the databases are reached through docker). Output goes to
  # backups/cron.log, because this host has no MTA and cron mail went nowhere: the
  # backup failed silently every night until 2026-10-10.
  CRON_DAILY="0 3 * * * cd \"$JSTACK_ROOT\" && bash scripts/core/backup_restore.sh backup --full >> \"$JSTACK_ROOT/backups/cron.log\" 2>&1"
  
  # Weekly cleanup (keep last 7 daily backups)
  CRON_CLEANUP="0 4 * * 0 find \"$JSTACK_ROOT/backups\" -name 'jstack_full_*.tar.gz' -mtime +7 -delete"
  
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

setup_site_logs_cron() {
  log "Setting up per-site container log cron jobs..."

  # Every 5 minutes, copy new container log lines into sites/<site>/logs/; daily,
  # rotate them (and logs/*.log) as this user. See scripts/core/site_logs.sh.
  CRON_PULL="*/5 * * * * bash \"$JSTACK_ROOT/scripts/core/site_logs.sh\" pull >> \"$JSTACK_ROOT/logs/site_logs.cron.log\" 2>&1"
  CRON_ROTATE="30 0 * * * bash \"$JSTACK_ROOT/scripts/core/site_logs.sh\" rotate >> \"$JSTACK_ROOT/logs/site_logs.cron.log\" 2>&1"

  if ! crontab -l 2>/dev/null | grep -q "site_logs.sh\" pull"; then
    (crontab -l 2>/dev/null; echo "$CRON_PULL") | crontab -
    log "Site log pull cron job added"
  else
    log "Site log pull cron job already exists"
  fi

  if ! crontab -l 2>/dev/null | grep -q "site_logs.sh\" rotate"; then
    (crontab -l 2>/dev/null; echo "$CRON_ROTATE") | crontab -
    log "Site log rotate cron job added"
  else
    log "Site log rotate cron job already exists"
  fi
}

create_backup_dir() {
  mkdir -p "$JSTACK_ROOT/backups"
  # Archives hold TLS private keys and every site's .env.
  chmod 700 "$JSTACK_ROOT/backups"
  mkdir -p "$JSTACK_ROOT/logs"
  log "Backup directories created"
}

remove_cron_jobs() {
  log "Removing JStack cron jobs..."
  crontab -l 2>/dev/null | grep -v "certbot renew" | grep -v "backup_restore.sh" | grep -v "jstack_full_.*tar.gz.*delete" | grep -v "site_logs.sh" | crontab -
  log "JStack cron jobs removed"
}

usage() {
  echo "Usage: $0 [install|remove|status]"
  echo "  install  - Set up SSL renewal, backup and site log cron jobs"
  echo "  remove   - Remove all JStack cron jobs"
  echo "  status   - Show current JStack cron jobs"
  exit 1
}

show_status() {
  log "Current JStack cron jobs:"
  crontab -l 2>/dev/null | grep -E "(certbot|backup_restore|jstack_full|site_logs)" || echo "No JStack cron jobs found"
}

main() {
  case "${1:-install}" in
    install)
      create_backup_dir
      setup_ssl_renewal_cron
      setup_backup_cron
      setup_site_logs_cron
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