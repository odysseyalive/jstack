#!/bin/bash
# JStack nginx layer-7 ban-guard check
# Usage: check_nginx_ban_guard.sh [conf_dir]
#
# Fails if any server block in a vhost lacks the fail2ban guard
#
#     if ($f2b_banned) { return 403; }
#
# Most web traffic reaches this host through Cloudflare, so a firewall ban on the
# client IP never matches a packet. The ban is enforced by nginx instead, via the
# geo map in conf.d/00-f2b-geo.conf -- but only in server blocks that test it.
# On 2026-09-16 (#906) a banned scanner drew 3000 redirects from the unguarded
# port-80 blocks while the guarded 443 block answered 403.
#
# Blocks that answer every request with `return 444` (close, no response) are
# skipped: they serve nothing a ban could protect.
#
# This check runs against the HOST's working tree, not against a git checkout:
# nginx/conf.d/*.conf is gitignored (generated per host), so a CI clone would
# contain no .conf files and the check would pass vacuously.

set -e

CONF_DIR="${1:-$(dirname "$0")/../../nginx/conf.d}"

if [ ! -d "$CONF_DIR" ]; then
  echo "No nginx conf dir at $CONF_DIR -- nothing to check."
  exit 0
fi

shopt -s nullglob
CONFS=("$CONF_DIR"/*.conf)
shopt -u nullglob

if [ ${#CONFS[@]} -eq 0 ]; then
  echo "No vhosts in $CONF_DIR -- nothing to check."
  exit 0
fi

echo "Checking ${#CONFS[@]} vhost(s) in $CONF_DIR for unguarded server blocks..."

FAILED=0

if ! grep -qE '^\s*geo\s+\$f2b_banned\b' "${CONFS[@]}"; then
  echo ""
  echo "FAIL: no 'geo \$f2b_banned' map in $CONF_DIR (expected in 00-f2b-geo.conf)."
  echo "Every guarded vhost will fail nginx -t with \"unknown variable\"."
  FAILED=1
fi

# Walk each file tracking brace depth; for every top-level `server {` block, report
# its opening line and server_name when it neither tests $f2b_banned nor returns 444.
# Comments are stripped first so a commented-out guard does not count.
OFFENDERS=$(awk '
  FNR == 1 { depth = 0; in_server = 0 }
  {
    line = $0
    sub(/#.*/, "", line)
    if (!in_server && depth == 0 && line ~ /^[ \t]*server[ \t]*\{/) {
      in_server = 1; start = FNR; name = "?"; guarded = 0; drop = 0
    }
    if (in_server) {
      if (line ~ /\$f2b_banned/) guarded = 1
      if (line ~ /^[ \t]*return[ \t]+444[ \t]*;/) drop = 1
      if (line ~ /^[ \t]*server_name[ \t]/) {
        name = line; sub(/^[ \t]*server_name[ \t]+/, "", name); sub(/[ \t]*;.*/, "", name)
      }
    }
    n = split(line, chars, "")
    for (i = 1; i <= n; i++) {
      if (chars[i] == "{") depth++
      else if (chars[i] == "}") {
        depth--
        if (in_server && depth == 0) {
          if (!guarded && !drop) printf "%s:%d  server_name %s\n", FILENAME, start, name
          in_server = 0
        }
      }
    }
  }
' "${CONFS[@]}")

if [ -n "$OFFENDERS" ]; then
  echo ""
  echo "FAIL: these server blocks do not enforce fail2ban bans; a banned IP is still served."
  echo ""
  echo "$OFFENDERS" | sed 's/^/  /'
  echo ""
  echo "Fix: add this line right after server_name in each block listed above."
  echo "  if (\$f2b_banned) { return 403; }"
  FAILED=1
fi

[ "$FAILED" -eq 0 ] || exit 1

echo "✓ Every server block enforces fail2ban bans."
