#!/bin/bash
# JStack Backup & Restore Script
# Location: scripts/core/backup_restore.sh

# -E carries the ERR trap into functions; pipefail makes a failed dump or tar inside a
# pipeline fail the run instead of being masked by the command after it.
set -eE -o pipefail
trap 'echo "[$(date "+%Y-%m-%d %H:%M:%S")] FAILED: line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR
# Scratch directories (the backup stage, validate's extraction dir) never outlive the run.
STAGE="" VALIDATE_TMP=""
trap 'rm -rf ${STAGE:+"$STAGE"} ${VALIDATE_TMP:+"$VALIDATE_TMP"}' EXIT

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

# The log file is best-effort. Until 2026-10-10 this was `echo | tee -a`, and logs/ was
# root-owned while the nightly cron ran as jarvis: tee failed on the first call, `set -e`
# ended the run before tar, and no archive was ever written. A log that cannot be written
# must never cost the backup, so the line always reaches stdout (cron sends it to
# backups/cron.log) and the file append is allowed to fail.
log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$line"
  { mkdir -p "$LOG_DIR" && echo "$line" >> "$LOG_DIR/backup_restore.log"; } 2>/dev/null || true
}

# Databases are dumped, never copied raw: a tar of a running Postgres data directory is
# not a consistent database. Each entry is
#   <site>|pg|<container>|<user>|<database>   pg_dump -Fc through `docker exec`
#   <site>|convex-export|<backend url>         `convex export --include-file-storage`
# Convex sites get both. The export is the one Convex itself restores from; the pg_dump
# is the whole database, system tables included, and costs nothing extra to keep.
# Dumps are staged under backups/ and enter the archive as sites/<site>/db-dumps/, so
# they ride under the sites/ root the restore contract already accepts, and no
# plaintext dump sits in a live site directory between runs.
# The URL is explicit because apps' .env carries no CONVEX_SELF_HOSTED_URL (its host
# port is 3220, sites/apps.odysseyalive.com/docker-compose.yml:110).
DB_DUMPS=(
  "apps.odysseyalive.com|pg|odyssey-apps-convex-postgres-1|convex|odyssey_apps"
  "apps.odysseyalive.com|convex-export|http://127.0.0.1:3220"
  "skul.odysseyalive.com|pg|odyssey-skul-convex-postgres-1|convex|odyssey_skul"
  "skul.odysseyalive.com|convex-export|http://127.0.0.1:3210"
)

# Live database directories the dumps replace, scratch dirs that churn while tar reads
# them, and build output or caches that are rebuilt from what is still archived
# (.next-prev is apps' previous build, kept for release-swap; trivy-cache is a scanner's
# vulnerability database, 1.4G on 2026-10-10 and re-downloaded on demand).
# data/convex-postgres stays IN: it is the backend's file storage on Postgres, it is
# small, and the export that also carries it has never been restored.
TAR_EXCLUDES=(
  --exclude='sites/*/data/postgres'
  --exclude='sites/*/data/*/tmp'
  --exclude='sites/*/.tmp'
  --exclude='*/node_modules'
  --exclude='*/.next'
  --exclude='*/.next-prev'
  --exclude='*/trivy-cache'
)

# cron's PATH reaches /usr/bin/node, which is v18 on this host, and the convex CLI dies
# on it at load (`Invalid flags supplied to RegExp constructor 'v'`, measured
# 2026-10-10). Use nvm's default node when there is one.
_convex_path() {
  local alias_file="$HOME/.nvm/alias/default" ver
  if [ -r "$alias_file" ]; then
    ver="$(cat "$alias_file")"
    if [ -x "$HOME/.nvm/versions/node/v${ver#v}/bin/node" ]; then
      echo "$HOME/.nvm/versions/node/v${ver#v}/bin:$PATH"
      return
    fi
  fi
  echo "$PATH"
}

# stage_dumps <stage dir>: write every DB_DUMPS entry under <stage>/sites/<site>/db-dumps/.
stage_dumps() {
  local stage="$1" entry site kind rest out site_dir
  for entry in "${DB_DUMPS[@]}"; do
    IFS='|' read -r site kind rest <<< "$entry"
    site_dir="$REPO_ROOT/sites/$site"
    out="$stage/sites/$site/db-dumps"
    mkdir -p "$out"
    case "$kind" in
      pg)
        local container user db
        IFS='|' read -r container user db <<< "$rest"
        log "Dumping $site Postgres ($db in $container)"
        docker exec "$container" pg_dump -U "$user" -d "$db" -Fc > "$out/$db.pgdump"
        ;;
      convex-export)
        log "Exporting $site Convex ($rest)"
        mkdir -p "$site_dir/.tmp"
        ( cd "$site_dir" && PATH="$(_convex_path)" CONVEX_SELF_HOSTED_URL="$rest" \
            CONVEX_TMPDIR="$site_dir/.tmp" ./node_modules/.bin/convex export \
            --include-file-storage --path "$out/convex-export.zip" ) > /dev/null
        ;;
      *)
        log "Unknown dump kind '$kind' for $site"
        exit 2
        ;;
    esac
  done
}

# The certbot tree is root-owned (the certbot container renews as root, every 12h,
# docker-compose.yml:28) and its private keys and accounts/ are root-only, so jarvis
# cannot tar it. A throwaway container reads it through a READ-ONLY mount and streams
# a tar that keeps root ownership and 0600 modes. Nothing is chmod'ed: the recursive
# 755 in fix_certbot_permissions.sh made every private key world-readable.
stage_certbot() {
  local stage="$1"
  mkdir -p "$stage/nginx"
  log "Streaming nginx/certbot/conf through a read-only container"
  docker run --rm -v "$REPO_ROOT/nginx/certbot/conf:/c:ro" alpine tar -C / -cf - c \
    > "$stage/nginx/certbot-conf.tar"
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
#
# The staged dumps and certbot tar join from a second -C, and that is safe for the same
# reason: the stage directory is laid out with the archive's own prefixes
# (sites/<site>/db-dumps/..., nginx/certbot-conf.tar), and each is named as a file, so
# no member is ever `./`.
backup_full() {
  TS=$(date '+%Y%m%d_%H%M%S')
  FILE="$BACKUP_DIR/jstack_full_$TS.tar.gz"
  # The archive holds TLS private keys, database dumps and every site's .env: owner-only.
  umask 077
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
  # One run at a time: a second run would race the first for the stage and the archive.
  exec 9> "$BACKUP_DIR/.lock"
  if ! flock -n 9; then
    log "Another backup is running (backups/.lock is held); not starting a second."
    exit 2
  fi
  STAGE="$BACKUP_DIR/.stage-$TS"
  mkdir -p "$STAGE"
  log "Starting full backup to $FILE (config: $JSTACK_CONFIG_NAME)"
  stage_dumps "$STAGE"
  stage_certbot "$STAGE"
  # The staged FILES join the archive, never their directories: the stage was made
  # under umask 077, and a `sites/` member at 0700 would reset the live sites/ to 0700
  # on restore (found in the 2026-10-10 restore drill), locking out nginx's workers.
  local staged=()
  mapfile -t staged < <(cd "$STAGE" && find sites nginx -type f)
  # Exit 1 from GNU tar means a file changed while it was read (a live site writes
  # logs and caches all night); the archive is still complete and validate_backup
  # below is the judge. 2 and up is a real failure.
  local rc=0
  tar czf "$FILE" -C "$REPO_ROOT" "${TAR_EXCLUDES[@]}" \
    --warning=no-file-changed --ignore-failed-read \
    docker-compose.yml \
    "$JSTACK_CONFIG_NAME" \
    nginx/conf.d \
    sites \
    -C "$STAGE" --no-recursion \
    "${staged[@]}" || rc=$?
  if [ "$rc" -gt 1 ]; then
    log "tar failed (exit $rc); removing the partial archive $FILE"
    rm -f "$FILE"
    exit 2
  fi
  log "Full backup written: $FILE ($(du -h "$FILE" | cut -f1))"
  validate_backup "$FILE"
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
  # The certbot tree went in as a root-owned tar (stage_certbot); it comes back the
  # same way, through a container, so the keys are root-owned 0600 again and the
  # certbot container can renew them.
  if [ -f "$REPO_ROOT/nginx/certbot-conf.tar" ]; then
    log "Restoring nginx/certbot/conf through a container (root-owned, modes kept)"
    mkdir -p "$REPO_ROOT/nginx/certbot/conf"
    docker run --rm -i -v "$REPO_ROOT/nginx/certbot/conf:/c" alpine tar -C / -xpf - \
      < "$REPO_ROOT/nginx/certbot-conf.tar"
    rm -f "$REPO_ROOT/nginx/certbot-conf.tar"
  fi
  # Databases are never loaded by a restore: that is a decision, per site, about
  # which copy wins. The dumps are left in sites/<site>/db-dumps/ for the runbook.
  if ls "$REPO_ROOT"/sites/*/db-dumps >/dev/null 2>&1; then
    log "Database dumps restored to sites/*/db-dumps/ and NOT loaded; load them by hand."
  fi
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
  case "$(basename "$FILE")" in
    jstack_full_*) _validate_full_contents "$FILE" ;;
  esac
}

# A full archive must also carry what backup_full staged, and each piece must be
# readable by the tool that would restore it. A dump that is present but empty, or an
# export taken without file storage, would otherwise pass every check above.
_validate_full_contents() {
  local file="$1" tmp entry site kind rest member toc
  VALIDATE_TMP="$(mktemp -d "$BACKUP_DIR/.validate-XXXXXX")"
  tmp="$VALIDATE_TMP"
  for entry in "${DB_DUMPS[@]}"; do
    IFS='|' read -r site kind rest <<< "$entry"
    case "$kind" in
      pg)
        local container user db
        IFS='|' read -r container user db <<< "$rest"
        member="sites/$site/db-dumps/$db.pgdump"
        tar xzf "$file" -C "$tmp" "$member"
        # Captured first: under pipefail, `pg_restore -l | grep -q` reads as a failure
        # when grep exits at its first match and pg_restore dies of SIGPIPE.
        toc="$(docker exec -i "$container" pg_restore -l < "$tmp/$member")"
        if ! grep -q 'TABLE DATA' <<< "$toc"; then
          log "Backup $file: $member does not list as a Postgres dump with table data"
          exit 2
        fi
        ;;
      convex-export)
        member="sites/$site/db-dumps/convex-export.zip"
        tar xzf "$file" -C "$tmp" "$member"
        # shellcheck source=/dev/null
        . "$REPO_ROOT/sites/$site/scripts/lib/convex-zip.sh"
        if ! UNZIP_DISABLE_ZIPBOMB_DETECTION=TRUE convex_zip_check "$tmp/$member"; then
          log "Backup $file: $member fails its check: $CONVEX_ZIP_ERROR"
          exit 2
        fi
        log "  $member: $CONVEX_ZIP_TABLES tables, $CONVEX_ZIP_FILES stored files"
        ;;
    esac
  done
  tar xzf "$file" -C "$tmp" nginx/certbot-conf.tar
  local listing
  listing="$(tar tf "$tmp/nginx/certbot-conf.tar")"
  if ! grep -qx 'c/accounts/' <<< "$listing" || ! grep -q '^c/live/' <<< "$listing"; then
    log "Backup $file: nginx/certbot-conf.tar is missing accounts/ or live/"
    exit 2
  fi
  log "Backup $file contents (dumps, exports, certbot): OK"
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
