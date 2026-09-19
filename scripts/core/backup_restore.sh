#!/bin/bash
# JStack Backup & Restore Script
# Location: scripts/core/backup_restore.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKUP_DIR="$REPO_ROOT/backups"
LOG_DIR="$REPO_ROOT/logs"
DOCKER_COMPOSE="$REPO_ROOT/docker-compose.yml"

# Which config file to archive: jstack.config when the operator has one, else the
# jstack.config.default template. Until 2026-09-19 this was hardcoded to the template,
# so a full backup — including the nightly one setup_cron_jobs.sh installs — carried
# DOMAIN=example.com and EMAIL=admin@example.com and no copy of the real values.
# shellcheck source=scripts/core/jstack_config.sh
. "$REPO_ROOT/scripts/core/jstack_config.sh"
JSTACK_CONFIG="$(_jstack_config_file)"
JSTACK_CONFIG_NAME="$(basename "$JSTACK_CONFIG")"

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

# ONE archive contract, shared by every function in this file: members are stored as
# paths RELATIVE TO $REPO_ROOT, and restore extracts with -C "$REPO_ROOT". Both halves
# are one design and neither can be read alone.
#
# Until 2026-09-19 backup_full() was:
#   tar czf "$FILE" -C "$REPO_ROOT" docker-compose.yml \
#     -C "$REPO_ROOT" "$JSTACK_CONFIG_NAME" \
#     -C "$REPO_ROOT/nginx/conf.d" . \
#     -C "$REPO_ROOT/nginx/certbot/conf" . \
#     -C "$REPO_ROOT" sites
# `-C` is a directory change for the READER and is not recorded in the archive, so that
# produced a FLAT archive: reproduced member list was `docker-compose.yml`,
# `jstack.config`, `./`, `./site.conf`, `sites/`, `sites/a/`, `sites/a/.env`. The
# `nginx/conf.d/` prefix was absent entirely, and because BOTH nginx directories were
# archived as `-C <dir> .` they collided into one `./` namespace. That loss happens at
# ARCHIVE time, so no smarter restore could undo it. Paired with the old
# `tar xzf "$FILE" -C /`, a restore run as root wrote `site.conf` to the filesystem root.
# See .claude/skills/awareness-ledger/ledger/patterns/PAT-2026-09-19-flat-tar-backup-unrestorable.md
#
# A single `-C "$REPO_ROOT"` with tree-shaped member names fixes both halves at once:
# every member carries its own prefix, so nginx/conf.d and nginx/certbot/conf stay
# distinguishable, and the archive can only be put back where it came from.
backup_full() {
  TS=$(date '+%Y%m%d_%H%M%S')
  FILE="$BACKUP_DIR/jstack_full_$TS.tar.gz"
  mkdir -p "$BACKUP_DIR"
  log "Starting full backup to $FILE (config: $JSTACK_CONFIG_NAME)"
  tar czf "$FILE" -C "$REPO_ROOT" \
    docker-compose.yml \
    "$JSTACK_CONFIG_NAME" \
    nginx/conf.d \
    nginx/certbot/conf \
    sites
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
      # Same two-`-C <dir> .` collision backup_full() carried, and the same fix: one
      # -C at $REPO_ROOT so conf.d and certbot/conf keep their own prefixes.
      tar czf "$FILE" -C "$REPO_ROOT" \
        nginx/conf.d \
        nginx/certbot/conf
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
      # `-C "$SITE_DIR" .` did not collide with anything — one -C, one tree — but it
      # stored `./`, `./.env`, ... , which under the restore rule below would unpack the
      # site's contents directly into $REPO_ROOT. Archiving `sites/$DOMAIN` from
      # $REPO_ROOT puts every archive this file writes under one contract.
      tar czf "$FILE" -C "$REPO_ROOT" "sites/$DOMAIN"
      log "Partial backup for site $DOMAIN completed: $FILE"
      ;;
    *)
      log "Unknown partial target: $TARGET"
      usage
      ;;
  esac
}

# Refuse an archive that cannot be put back where it came from, INSTEAD of extracting it
# wrongly. Every member of a jstack archive must live under one of the four roots this
# file writes; anything else means the archive was built to a different contract.
#
# The case this exists for: archives written before 2026-09-19 are flat (see
# backup_full()'s header). Extracting one with -C "$REPO_ROOT" would drop a bare
# `site.conf` into the repo root and leave nginx/conf.d untouched — a restore that
# reports success and restores nothing. There is no correct way to unpack them, because
# the two nginx directories were conflated at archive time, so refusing with an
# explanation is the only honest answer. As of 2026-09-19 this host has no such archive
# in backups/ (the directory holds one unrelated subdirectory and no jstack_*.tar.gz),
# so the guard costs nothing here and protects any copy kept elsewhere.
#
# `|| true` keeps a no-match grep from aborting the script under `set -e`.
_assert_restorable() {
  local file="$1" offenders
  offenders="$(tar tzf "$file" | grep -vE '^(docker-compose\.yml|jstack\.config(\.default)?|nginx/|sites/)' | head -5 || true)"
  if [ -n "$offenders" ]; then
    log "REFUSING $file: it is not a restorable jstack archive."
    log "  Members outside the expected roots (docker-compose.yml, jstack.config, nginx/, sites/):"
    printf '%s\n' "$offenders" | while IFS= read -r member; do
      log "    $member"
    done
    log "  A member beginning './' means a FLAT archive written before 2026-09-19."
    log "  Those cannot be restored: nginx/conf.d and nginx/certbot/conf were merged"
    log "  into one namespace when the archive was written. Unpack it by hand into an"
    log "  empty directory and sort the files out there."
    exit 2
  fi
}

restore_backup() {
  FILE="$1"
  if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    log "Restore needs an existing backup file. Got: '${FILE:-<none>}'"
    exit 2
  fi
  _assert_restorable "$FILE"
  # -C "$REPO_ROOT", never "/". The archive's members are relative to the repo root by
  # construction, so extracting at / scattered them across the filesystem.
  log "Restoring from backup $FILE into $REPO_ROOT"
  tar xzf "$FILE" -C "$REPO_ROOT"
  log "Restore completed."
}

# Integrity AND restorability. `tar tzf >/dev/null` alone proves only that the gzip
# stream parses and the headers are well formed — it passes on the flat archives that
# cannot be restored at all, which is an instance of the defect rather than evidence
# against it. A backup nobody can put back is not a backup.
validate_backup() {
  FILE="$1"
  if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    log "Validate needs an existing backup file. Got: '${FILE:-<none>}'"
    exit 2
  fi
  log "Validating backup $FILE"
  if tar tzf "$FILE" >/dev/null; then
    log "Backup $FILE integrity: OK"
  else
    log "Backup $FILE integrity: FAILED"
    exit 2
  fi
  _assert_restorable "$FILE"
  log "Backup $FILE restorable under $REPO_ROOT: OK"
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
