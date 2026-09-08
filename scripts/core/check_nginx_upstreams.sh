#!/bin/bash
# JStack nginx upstream-resolution check
# Usage: check_nginx_upstreams.sh [conf_dir]
#
# Fails if any generated vhost names its upstream as a literal hostname in
# proxy_pass. nginx resolves such a hostname at CONFIG-PARSE time, so if the
# named container is not running when nginx starts, nginx refuses to start AT
# ALL -- every vhost goes down, not just the offending one.
#
# This happened on 2026-09-08 (#868): a docker-ce upgrade restarted the daemon,
# jstack_nginx_1 came up before odyssey-apps-convex-backend-1 and died with
# "host not found in upstream", restarting 9 times over 57 seconds with ports
# 80/443 serving nothing.
#
# The safe pattern, emitted by setup_service_subdomains_ssl.sh and documented as
# PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams:
#
#     resolver 127.0.0.11 valid=10s ipv6=off;
#     set $upstream_site http://container:port;
#     proxy_pass $upstream_site;
#
# A proxy_pass argument containing a variable is resolved per request instead.
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

echo "Checking ${#CONFS[@]} vhost(s) in $CONF_DIR for parse-time upstreams..."

# A literal upstream is proxy_pass followed by a scheme and an alphabetic host.
# proxy_pass $var; and proxy_pass http://127.0.0.1:port; are both fine -- the
# former resolves per request, the latter needs no resolution at all.
OFFENDERS=$(grep -lE '^\s*proxy_pass\s+https?://[A-Za-z]' "${CONFS[@]}" 2>/dev/null || true)

if [ -n "$OFFENDERS" ]; then
  echo ""
  echo "FAIL: these vhosts resolve their upstream at nginx START time."
  echo "One unavailable container will stop nginx from starting, taking down ALL sites."
  echo ""
  for f in $OFFENDERS; do
    echo "  $f"
    grep -nE '^\s*proxy_pass\s+https?://[A-Za-z]' "$f" | sed 's/^/      /'
  done
  echo ""
  echo "Fix: give the vhost a resolver and pass the upstream through a variable."
  echo "  resolver 127.0.0.11 valid=10s ipv6=off;"
  echo "  set \$upstream_site http://container:port;"
  echo "  proxy_pass \$upstream_site;"
  exit 1
fi

echo "✓ No parse-time upstreams. nginx can start with any backend down."
