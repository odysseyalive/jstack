#!/bin/bash
# JStack Per-Site Container Logs
# Location: scripts/core/site_logs.sh
# Usage: site_logs.sh pull [<domain>] | rotate
#
# Every site's container logs land in sites/<site>/logs/<service>.log, owned by the
# jstack user. Docker's own copy (json-file under /var/lib/docker, root-only) is kept
# only as a bounded buffer: each site's compose caps it with `logging: max-size 10m,
# max-file 3`.
#
# WHY A PULL AND NOT A FOLLOWER. A long-running `docker compose logs -f` per site needs
# something to keep it alive: systemd --user needs linger (`loginctl enable-linger`,
# root), and a cron @reboot follower dies with every compose restart. jstack schedules
# everything from the user's crontab and runs no daemons of its own, so cron calls
# `pull` every 5 minutes and it copies the window since the last pull. It holds no
# state but a cursor file per site.
#
# The one gap: lines a container wrote after the last pull are lost if the container
# is recreated before the next one. Run `site_logs.sh pull <domain>` right before
# `docker compose up -d` on a site to close it.
#
# THE WINDOW. `docker logs --since` and `--until` are BOTH inclusive to the nanosecond
# (measured 2026-10-10: a line stamped exactly T appears under `--since T` and under
# `--until T`), so the next cursor is the last --until plus 1ns. --until stays 2s
# behind now, so a line the daemon has stamped but not yet written is not skipped.
#
# Containers are found by compose's working_dir label, not by parsing compose files,
# so services behind a profile (next-app under `prod`) are pulled like any other, and
# a stopped container's last lines are still collected.

set -eE -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SITES_DIR="$REPO_ROOT/sites"
LOG_DIR="$REPO_ROOT/logs"

usage() {
  echo "Usage: $0 pull [<domain>] | rotate"
  echo "  pull    copy new container log lines into sites/<site>/logs/<service>.log"
  echo "  rotate  rotate sites/*/logs/*.log and logs/*.log (daily, keep 14) as this user"
  exit 1
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# pull_site <site dir>: append each container's new lines to logs/<service>.log.
pull_site() {
  local site_dir="$1" logs cursor since until secs nsec name service
  logs="$site_dir/logs"
  cursor="$logs/.cursor"
  mkdir -p "$logs"
  # No cursor yet: take everything Docker still buffers for this site.
  since="$(cat "$cursor" 2>/dev/null || echo 0)"
  secs="$(( $(date +%s) - 2 ))"
  nsec="$(date +%N)"
  until="$secs.$nsec"
  while IFS='|' read -r name service; do
    [ -n "$name" ] || continue
    docker logs --timestamps --since "$since" --until "$until" "$name" \
      >> "$logs/${service:-$name}.log" 2>&1
  done < <(docker ps -a --filter "label=com.docker.compose.project.working_dir=$site_dir" \
             --format '{{.Names}}|{{.Label "com.docker.compose.service"}}')
  # Next window starts 1ns after this one ended (10#: %N can begin with zeros).
  nsec="$(( 10#$nsec + 1 ))"
  if [ "$nsec" -ge 1000000000 ]; then
    secs="$(( secs + 1 ))"; nsec=0
  fi
  printf '%s.%09d\n' "$secs" "$nsec" > "$cursor.tmp"
  mv "$cursor.tmp" "$cursor"
}

pull() {
  local only="$1" site_dir
  exec 9> "$LOG_DIR/.site_logs.lock"
  if ! flock -n 9; then
    log "Another pull is running; skipping this one."
    return 0
  fi
  for site_dir in "$SITES_DIR"/*/; do
    site_dir="${site_dir%/}"
    [ -f "$site_dir/docker-compose.yml" ] || continue
    if [ -n "$only" ] && [ "$(basename "$site_dir")" != "$only" ]; then
      continue
    fi
    pull_site "$site_dir"
  done
}

# Runs logrotate as this user against a config written here, with its own state file:
# nothing in /etc is involved, so the rotated files stay the user's. No `create`: the
# next pull's `>>` makes the new file, and nothing holds the old one open (a pull
# opens its log for the length of one `docker logs` call), so a plain rename is safe.
rotate() {
  local conf="$LOG_DIR/site_logs.logrotate.conf"
  cat > "$conf" <<EOF
$SITES_DIR/*/logs/*.log $LOG_DIR/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d
}
EOF
  chmod 644 "$conf"
  /usr/sbin/logrotate -s "$LOG_DIR/site_logs.logrotate.state" "$conf"
}

main() {
  # Container output can carry user data (emails, request paths), and a site directory
  # is world-readable: the logs are the owner's alone.
  umask 077
  mkdir -p "$LOG_DIR"
  case "${1:-}" in
    pull)   pull "${2:-}" ;;
    rotate) rotate ;;
    *)      usage ;;
  esac
}

main "$@"
