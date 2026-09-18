#!/bin/bash
# JStack TLS vhost hardening conformance check
# Usage: check_vhost_hardening.sh [conf_dir]
#
# Answers one question: does every TLS vhost on this host still carry the security
# directives that scripts/core/setup_service_subdomains_ssl.sh emits for a NEW site?
#
# The generator's upgrade_site_to_https() heredoc is the definition of a conforming
# 443 block. A vhost hand-edited after generation, or generated before a directive
# was added, silently drops behind it -- so a security fix put into the generator is
# live on the newest site and absent from the other seven. This check names the gap.
#
# Asserted, per top-level server block that listens on 443:
#   * add_header X-Frame-Options / X-Content-Type-Options / X-XSS-Protection /
#     Strict-Transport-Security / Referrer-Policy, each with the trailing `always`.
#     Without `always` nginx drops the header on every 4xx/5xx, which is most
#     scanner traffic.
#   * a Content-Security-Policy or Content-Security-Policy-Report-Only header.
#   * limit_req zone=perip and limit_conn conperip (the zones live in the http block
#     of nginx/nginx.conf).
#   * resolver, but only when the block proxies. A parse-time upstream hostname makes
#     nginx refuse to START when the container is down, taking every vhost with it.
#     See PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams.
#
# NOT asserted here: the `if ($f2b_banned) { return 403; }` guard. That invariant
# belongs to check_nginx_ban_guard.sh, which covers both the 80 and the 443 blocks.
# Two checks claiming one invariant is a defect, not redundancy -- run both.
#
# Redirect-only TLS blocks are a class of their own: a top-level 443 block whose body
# holds a `return 301` and no `location` and no `proxy_pass`, such as the hand-written
# www -> apex redirect in odysseyalive.com.conf. It emits no body and has no upstream,
# so CSP, X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy and
# resolver govern nothing there, and the rate limits are left off because the block does
# no per-request work. HSTS is NOT in that list and is asserted: a browser that reaches
# https://www.<domain> takes the 301, and without Strict-Transport-Security that hostname
# is never pinned, so the next visit to it can start over plain HTTP.
#
# Skipped: blocks that do not listen on 443 (the generator's port-80 block is a
# redirect and carries no headers by design), and blocks that answer `return 444`
# (close, no response -- they serve nothing a header could protect). Comments are
# stripped before matching, so a commented-out directive does not count as present.
# Dead *.watchman-bak-* backups in conf.d are not live vhosts and are skipped.
#
# Read-only: this script inspects. It never writes, reloads, or regenerates, and it
# never calls docker.
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
ALL=("$CONF_DIR"/*.conf)
shopt -u nullglob

# Drop dead backups; keep only live vhosts.
CONFS=()
for f in "${ALL[@]}"; do
  case "$f" in
    *.watchman-bak-*) continue ;;
  esac
  CONFS+=("$f")
done

if [ ${#CONFS[@]} -eq 0 ]; then
  echo "No vhosts in $CONF_DIR -- nothing to check."
  exit 0
fi

echo "Checking ${#CONFS[@]} vhost(s) in $CONF_DIR for TLS hardening drift..."

# Walk each file tracking brace depth. For every top-level `server {` block that
# listens on 443, report its opening line, its server_name, and EVERY directive the
# generator emits that the block is missing -- not just the first.
OFFENDERS=$(awk '
  # Patterns are passed as STRINGS: a /regex/ constant handed to an awk function is
  # evaluated as ($0 ~ /regex/) at the call site, which would test the current line
  # instead of the block body and pass vacuously.
  function seen(pat) { return (body ~ pat) }
  function lseen(pat) { return (lbody ~ pat) }
  function hdr(name,   p) {
    # add_header <name> <value...> always;  -- `always` is required.
    p = "(^|\n)[ \t]*add_header[ \t]+" name "[ \t][^\n]*[ \t]always[ \t]*;"
    return (lbody ~ tolower(p))
  }
  function want(ok, what) { if (!ok) miss = miss sprintf("      missing: %s\n", what) }

  FNR == 1 { depth = 0; in_server = 0 }
  {
    line = $0
    sub(/#.*/, "", line)
    if (!in_server && depth == 0 && line ~ /^[ \t]*server[ \t]*\{/) {
      in_server = 1; start = FNR; name = "?"; body = ""
    }
    if (in_server) {
      body = body "\n" line
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
          in_server = 0
          lbody = tolower(body)
          # Only TLS blocks that serve something.
          if (seen("(^|\n)[ \t]*listen[ \t]+[^;\n]*443[ \t;]") &&
              !seen("(^|\n)[ \t]*return[ \t]+444[ \t]*;")) {
            miss = ""
            hsts = "add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;"
            # Redirect-only block: a 301 and nothing else -- no location, no proxy_pass.
            # It emits no body and has no upstream, so only HSTS is asserted on it.
            if (seen("(^|\n)[ \t]*return[ \t]+301[ \t]") &&
                !seen("(^|\n)[ \t]*location[ \t]") &&
                !seen("(^|\n)[ \t]*proxy_pass[ \t]")) {
              want(hdr("Strict-Transport-Security"), hsts "   (redirect-only block)")
            } else {
              want(hdr("X-Frame-Options"),           "add_header X-Frame-Options SAMEORIGIN always;")
              want(hdr("X-Content-Type-Options"),    "add_header X-Content-Type-Options nosniff always;")
              want(hdr("X-XSS-Protection"),          "add_header X-XSS-Protection \"1; mode=block\" always;")
              want(hdr("Strict-Transport-Security"), hsts)
              want(hdr("Referrer-Policy"),           "add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;")
              want(lseen("(^|\n)[ \t]*add_header[ \t]+content-security-policy"),
                   "add_header Content-Security-Policy-Report-Only \"default-src '\''self'\''; ...\" always;")
              want(seen("(^|\n)[ \t]*limit_req[ \t]+zone=perip[ \t;]"),
                   "limit_req zone=perip burst=50 nodelay;")
              want(seen("(^|\n)[ \t]*limit_conn[ \t]+conperip[ \t;]"),
                   "limit_conn conperip 20;")
              if (seen("(^|\n)[ \t]*proxy_pass[ \t]"))
                want(seen("(^|\n)[ \t]*resolver[ \t]"), "resolver 127.0.0.11 valid=10s ipv6=off;   (block proxies)")
            }
            if (miss != "") printf "%s:%d  server_name %s\n%s", FILENAME, start, name, miss
          }
          body = ""
        }
      }
    }
  }
' "${CONFS[@]}")

if [ -n "$OFFENDERS" ]; then
  echo ""
  echo "FAIL: these TLS server blocks have drifted from what the site generator emits."
  echo ""
  echo "$OFFENDERS" | sed 's/^/  /'
  echo ""
  echo "Fix: add the listed directives to each block, and put the fix in the generator"
  echo "     (scripts/core/setup_service_subdomains_ssl.sh, upgrade_site_to_https) first"
  echo "     -- a directive typed into nginx/conf.d/<domain>.conf reaches that one site"
  echo "     until its next regeneration, and no other site ever."
  echo ""
  echo "The fail2ban ban guard is a separate invariant: check_nginx_ban_guard.sh."
  exit 1
fi

echo "✓ Every TLS server block carries the generator's security directives."
