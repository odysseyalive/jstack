#!/bin/bash
# Per-site nginx config + SSL helpers used by `jstack.sh --install-site`.
#
# Provides:
#   generate_site_nginx_config <domain> <port> [container]
#     Writes nginx/conf.d/<domain>.conf with:
#       - HTTP server: ACME challenge location + proxy_pass (used before cert exists)
#   install_site_ssl_certificate <domain>
#     Acquires a Let's Encrypt cert for the single given domain via the shared certbot.
#   upgrade_site_to_https <domain> <port> [container]
#     After cert acquisition, rewrites the config to HTTPS+proxy_pass and adds an HTTP→HTTPS redirect.
#     Dispatches on the site's profile (see _site_profile below).
#   upgrade_connector_site_to_https <domain> <port> [container]
#     The `connector` profile: an SSE / Streamable-HTTP MCP endpoint (a claude.ai remote
#     connector). Same hardening contract as the standard profile, different proxy tuning.
#
# PROFILES
#   A site picks its profile with `SITE_PROFILE=<name>` in sites/<domain>/.env, or by
#   exporting SITE_PROFILE before the call. Unset means `standard`.
#     standard   — a website. Buffered proxy, 60s timeouts, websocket Upgrade header.
#     webhook    — an API / webhook / database endpoint that serves no HTML: the Convex
#                  backends behind appshook and skulhook. Emitted by the SAME function
#                  as `standard` and byte-identical to it everywhere except the CSP,
#                  which is the minimal `default-src 'self'; frame-ancestors <fa>;
#                  base-uri 'self'`. Promoted 2026-09-18 from the live vhosts: an
#                  endpoint that serves no HTML has no script or style to govern, and
#                  handing it the standard policy would ADD 'unsafe-inline' to
#                  script-src and style-src on two vhosts that do not carry it today.
#                  That is a loosening, so the minimal form is the generated one.
#     connector  — an MCP/SSE endpoint. Unbuffered, 1h timeouts, Connection "" (SSE dies
#                  under buffering and under a 60s read timeout), server_tokens off,
#                  http2 on. (Cloudflare real-IP trust is NOT here: it is declared once
#                  at http level in nginx/nginx.conf and applies to every server block.)
#   All three profiles emit the SAME security directives, so check_vhost_hardening.sh and
#   check_nginx_ban_guard.sh pass on any of them. A profile is a proxy-tuning variant (or,
#   for `webhook`, a CSP that is STRICTER), never a hardening exemption: a header added to
#   one profile belongs in all of them.
#
# OPTIONS (per site, read from sites/<domain>/.env with an ANCHORED grep, or exported
# under the same name before the call — see _site_env_value)
#   SITE_PROFILE=standard|webhook|connector
#                                     — see PROFILES above. Unset means `standard`.
#   SITE_WWW_REDIRECT=1               — also emit a `www.<domain>` -> apex 301 block.
#                                       Unset means NO www block; see _site_www_redirect.
#   SITE_XFRAME=SAMEORIGIN|DENY       — the X-Frame-Options value. Default SAMEORIGIN;
#                                       see _site_xframe for why the stricter value is
#                                       NOT the default.
#   SITE_CSP_FRAME_ANCESTORS=self|none
#                                     — the CSP frame-ancestors value. Default self.
#                                       Keep it in step with SITE_XFRAME: DENY pairs
#                                       with none, SAMEORIGIN pairs with self.
#   SITE_CSP_SCRIPT_EXTRA=<sources>   — extra CSP script-src sources, space separated,
#                                       e.g. "https://challenges.cloudflare.com".
#   SITE_CSP_CONNECT_EXTRA=<sources>  — extra CSP connect-src sources, e.g.
#                                       "https://foohook.example.com wss://foohook.example.com"
#                                       for a site whose Convex/websocket backend is on
#                                       its own subdomain. (Was the exported-only
#                                       `csp_connect_extra`, which nothing set, so every
#                                       regeneration silently dropped these.)
#   SITE_CSP_FRAME_SRC=<sources>      — emit a CSP frame-src directive holding EXACTLY
#                                       these sources. Unset emits no frame-src at all,
#                                       so default-src 'self' governs. 'self' is not
#                                       added for you: a site that frames both itself and
#                                       a third party lists "'self' https://…" here.
#   The three CSP source options are rejected with an error on the `webhook` profile,
#   whose policy has no script-src, connect-src or frame-src to extend. Silently
#   ignoring them would be worse.
#
# TESTING HOOK
#   NGINX_CONF_DIR=<dir> makes every emitter write there instead of nginx/conf.d. It
#   exists so the generator's output can be diffed against the live vhosts WITHOUT
#   writing into nginx/conf.d — the only way to prove parity without touching a file
#   that is serving traffic. Unset, behaviour is exactly as before.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/jstack.config"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  # shellcheck disable=SC1090
  source "$REPO_ROOT/jstack.config.default" 2>/dev/null || true
fi

# _match_conf_dir_perms / _conf_target_mode. Shared with apply_vhost_change.sh, which
# writes into the same directory and needs the same answer. Source-only: it sets no
# shell options and runs nothing, so it is safe to pull in either side of the config
# load above.
# shellcheck source=scripts/core/nginx_conf_perms.sh
. "$REPO_ROOT/scripts/core/nginx_conf_perms.sh"

DOMAIN="${DOMAIN:-example.com}"
EMAIL="${EMAIL:-admin@example.com}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Resolve the proxy target. If a container name is given, use docker DNS; otherwise
# fall back to the host bridge IP.
_proxy_target() {
  local site_port="$1"
  local site_container="$2"
  if [ -n "$site_container" ]; then
    echo "http://${site_container}:${site_port}"
  else
    echo "http://172.17.0.1:${site_port}"
  fi
}

# watchman 2026-09-16 (#906): every generated server block tests $f2b_banned, which is
# declared in conf.d/00-f2b-geo.conf. conf.d/*.conf is gitignored, so a fresh clone has
# neither that file nor the fail2ban-maintained list it includes, and nginx -t would fail
# with "unknown variable". Create both if missing; never overwrite existing ones.
_ensure_f2b_geo() {
  local nginx_conf_dir="$1"
  local geo_conf="$nginx_conf_dir/00-f2b-geo.conf"
  local geo_list="$nginx_conf_dir/f2b-banned.geo"

  if [ ! -f "$geo_list" ]; then
    log "Creating empty fail2ban ban list $geo_list"
    : >"$geo_list"
    _match_conf_dir_perms "$nginx_conf_dir" "$geo_list"
  fi

  if [ ! -f "$geo_conf" ]; then
    log "Creating $geo_conf (layer-7 fail2ban ban map)"
    cat >"$geo_conf" <<'EOF'
# Layer-7 fail2ban ban list, loaded into the http block via nginx.conf's
# `include /etc/nginx/conf.d/*.conf`. Kept here, not in nginx.conf, because
# nginx.conf is a single-file bind mount: editing it on the host swaps the inode and
# the running container never sees the change until it is recreated.
#
# Most web traffic arrives from Cloudflare edge IPs, so a firewall (nft) ban on the
# client IP never matches a packet. geo evaluates the realip-restored address, i.e.
# the true client behind Cloudflare. fail2ban's jstack-nginx-geo action maintains
# f2b-banned.geo; every public server block does
# `if ($f2b_banned) { return 403; }` - removing this file makes nginx refuse to start.
geo $f2b_banned {
    default 0;
    include /etc/nginx/conf.d/f2b-banned.geo;
}
EOF
    _match_conf_dir_perms "$nginx_conf_dir" "$geo_conf"
  fi
}

# One per-site option, resolved once: an exported variable of the SAME NAME wins,
# otherwise the `<KEY>=` line in sites/<domain>/.env, otherwise empty. Prints without a
# trailing newline so callers can use the value inside a header string.
#
# The grep is ANCHORED. See PAT-2026-09-02-jstack-env-unanchored-grep: jstack.sh:118-120
# reads this same .env with `grep -m1 PORT`, which matches the first line CONTAINING
# "PORT" — a comment, or PLAYWRIGHT_MCP_PORT — and silently builds the vhost against the
# wrong upstream. '^<KEY>=' cannot be won by a comment or by a longer key.
#
# ONE copy of this lookup, not one per option: there are seven options now, and seven
# hand-written greps are seven chances for the anchor to be dropped from one of them.
# The `| cut` also keeps this safe under `set -e` — a pipeline's status is cut's, so a
# no-match grep does not abort the run.
_site_env_value() {
  local site_domain="$1" key="$2"
  local from_export="${!key:-}"
  if [ -n "$from_export" ]; then
    printf '%s' "$from_export"
    return 0
  fi
  local site_env="$REPO_ROOT/sites/${site_domain}/.env"
  if [ -f "$site_env" ]; then
    grep -m1 "^${key}=" "$site_env" | cut -d= -f2- | tr -d '\n'
  fi
}

# Which vhost profile a site gets: SITE_PROFILE, else `standard`.
#
# An unrecognised profile name is NOT silently treated as `standard`: that would hand a
# connector the buffered 60s proxy config and break its SSE stream with no error anywhere.
_site_profile() {
  local from_env
  from_env="$(_site_env_value "$1" SITE_PROFILE)"
  if [ -n "$from_env" ]; then
    echo "$from_env"
    return 0
  fi
  echo "standard"
}

# The X-Frame-Options value for a site: SITE_XFRAME, else SAMEORIGIN.
#
# WHY SAMEORIGIN IS THE DEFAULT AND NOT THE STRICTER DENY. X-Frame-Options: DENY refuses
# ALL framing, including a page framing itself on its own origin — it is not "SAMEORIGIN
# plus a bit". skul.odysseyalive.com does exactly that: the game player at
# sites/skul.odysseyalive.com/src/components/modules/EmbeddedPlayer.tsx renders an
# <iframe> whose src is the same-origin /modules/<slug>/play.html and talks to it over
# postMessage. A DENY default would blank that player on the next regeneration, with no
# error anywhere but the browser console. So the default is the value four of this
# host's five HTML-serving vhosts already carry, and the one site that is stricter
# (odysseyalive.com, DENY since the 2026-06-19 hardening) declares SITE_XFRAME=DENY.
#
# An unrecognised value is an ERROR, not a fallback to the default: a typo must not
# quietly downgrade a site that asked for DENY.
_site_xframe() {
  local raw
  raw="$(_site_env_value "$1" SITE_XFRAME)"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    ''|sameorigin) printf 'SAMEORIGIN' ;;
    deny) printf 'DENY' ;;
    *)
      log "ERROR: unknown SITE_XFRAME '$raw' for $1 (want: SAMEORIGIN|DENY)" >&2
      return 1
      ;;
  esac
}

# The CSP frame-ancestors value for a site, already quoted: SITE_CSP_FRAME_ANCESTORS,
# else 'self'. Same default and the same reason as _site_xframe — frame-ancestors 'none'
# is the CSP spelling of X-Frame-Options: DENY and breaks the same same-origin iframe.
#
# Restricted to the two keywords on purpose. Allowing a free-text source list here would
# let a typo ("selff") through as a policy that matches nothing, or a stray `*` through
# as a policy that matches everything; both fail silently under Report-Only. A site that
# genuinely needs a named parent origin is a generator change, not an .env line.
_site_csp_frame_ancestors() {
  local raw
  raw="$(_site_env_value "$1" SITE_CSP_FRAME_ANCESTORS)"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d "'")" in
    ''|self) printf "'self'" ;;
    none) printf "'none'" ;;
    *)
      log "ERROR: unknown SITE_CSP_FRAME_ANCESTORS '$raw' for $1 (want: self|none)" >&2
      return 1
      ;;
  esac
}

# The Content-Security-Policy-Report-Only VALUE for a site, built from its profile and
# its CSP options. One builder for all three profiles, so a directive added to the policy
# cannot reach two of them and miss the third.
#
#   _site_csp_value <domain> <profile>
#
# The `webhook` shape is deliberately minimal: an endpoint serving JSON, websockets or a
# database protocol has no script, style, image or font to govern, and default-src 'self'
# already denies everything it does not name. Extending it is refused rather than
# ignored — a SITE_CSP_CONNECT_EXTRA that silently vanished would be found the day the
# policy is promoted to enforcing, which is the worst possible day.
_site_csp_value() {
  local site_domain="$1" site_profile="$2"
  local script_extra connect_extra frame_src frame_ancestors
  script_extra="$(_site_env_value "$site_domain" SITE_CSP_SCRIPT_EXTRA)"
  connect_extra="$(_site_env_value "$site_domain" SITE_CSP_CONNECT_EXTRA)"
  frame_src="$(_site_env_value "$site_domain" SITE_CSP_FRAME_SRC)"
  frame_ancestors="$(_site_csp_frame_ancestors "$site_domain")" || return 1

  if [ "$site_profile" = "webhook" ]; then
    if [ -n "$script_extra$connect_extra$frame_src" ]; then
      log "ERROR: SITE_PROFILE=webhook takes no CSP source extras for $site_domain" >&2
      log "       (its policy has no script-src, connect-src or frame-src to extend)" >&2
      return 1
    fi
    printf "default-src 'self'; frame-ancestors %s; base-uri 'self'" "$frame_ancestors"
    return 0
  fi

  printf "default-src 'self'; script-src 'self' 'unsafe-inline'%s; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'%s;%s frame-ancestors %s; base-uri 'self'; form-action 'self'" \
    "${script_extra:+ $script_extra}" \
    "${connect_extra:+ $connect_extra}" \
    "${frame_src:+ frame-src $frame_src;}" \
    "$frame_ancestors"
}

# Does this site also answer on www.<domain>? OPT-IN, per site:
#   SITE_WWW_REDIRECT=1 in sites/<domain>/.env, or exported before the call.
# Anything else -- absent, empty, 0, false, no -- means NO www block, and that is the
# right default here: six of this host's seven domains are subdomains, where
# www.<subdomain> is in neither DNS nor any certificate. Only an apex opts in.
#
# Resolved by _site_env_value, so it gets the same ANCHORED grep as every other option
# (PAT-2026-09-02-jstack-env-unanchored-grep): an unanchored match would be won by a
# comment that merely mentions the key.
#
# PRECONDITION the caller owns: the site's certificate must carry www.<domain> as a SAN,
# because the emitted block serves the SAME cert as the apex. Verified 2026-09-18 for the
# one site that opts in today:
#   openssl x509 -noout -ext subjectAltName \
#     -in nginx/certbot/conf/live/odysseyalive.com/fullchain.pem
#   -> DNS:odysseyalive.com, DNS:www.odysseyalive.com
# Opting in a site whose cert lacks that SAN makes every browser reject the www hostname
# outright, which is worse than having no www block at all.
_site_www_redirect() {
  local raw
  raw="$(_site_env_value "$1" SITE_WWW_REDIRECT)"
  case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# The extra name the PORT-80 block must also answer on, or empty. Without this,
# http://www.<domain> never reaches this vhost at all: it falls through to the port-80
# default_server in default.conf and is served the setup landing page, so the www
# hostname would never be redirected and never be pinned.
_www_server_name_suffix() {
  if _site_www_redirect "$1"; then printf ' www.%s' "$1"; fi
}

# The `www.<domain>` -> apex 301 block, or nothing when the site has not opted in.
# Prints a LEADING blank line and no trailing one; callers add the trailing newline, so
# the not-opted-in case reproduces the previous output byte for byte.
#
# Promoted 2026-09-18 from the hand-written third server block in
# nginx/conf.d/odysseyalive.com.conf, which no generator path emitted -- a domain the
# generator cannot reproduce is a domain that silently falls out of every future fix.
#
# It carries HSTS, and that is the security fix. A browser reaching
# https://www.<domain> takes this 301; without Strict-Transport-Security the www
# hostname is never pinned, so the NEXT visit to it can start over plain HTTP and be
# intercepted before the redirect ever runs. check_vhost_hardening.sh asserts exactly
# this on redirect-only TLS blocks.
#
# Nothing else from the hardened block belongs here: there is no body to protect
# (X-Frame-Options, CSP, X-Content-Type-Options, Referrer-Policy govern content this
# block never emits) and no upstream to resolve, so the rate limits and the resolver
# are left off too. The $f2b_banned guard IS emitted -- check_nginx_ban_guard.sh covers
# every server block, and a banned scanner must not be handed a 301 either (#906).
_www_redirect_block() {
  local site_domain="$1" cert_line="$2" key_line="$3"
  _site_www_redirect "$site_domain" || return 0
  cat <<EOF

# www.${site_domain} -> apex. Emitted because SITE_WWW_REDIRECT=1 for this site.
# Serves the apex certificate, which must list www.${site_domain} as a SAN.
server {
    listen 443 ssl;
    server_name www.${site_domain};

    # watchman 2026-09-16 (#906): layer-7 fail2ban ban (see conf.d/00-f2b-geo.conf).
    if (\$f2b_banned) { return 403; }

    ${cert_line}
    ${key_line}

    # Pins the www hostname too. Without it this 301 teaches the browser nothing and
    # the next request to www can start over plain HTTP.
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    return 301 https://${site_domain}\$request_uri;
}
EOF
}

generate_site_nginx_config() {
  local site_domain="$1"
  local site_port="$2"
  local site_container="$3"

  if [ -z "$site_domain" ] || [ -z "$site_port" ]; then
    log "ERROR: generate_site_nginx_config requires domain and port"
    return 1
  fi

  local proxy_target
  proxy_target=$(_proxy_target "$site_port" "$site_container")
  local nginx_conf_dir="${NGINX_CONF_DIR:-$REPO_ROOT/nginx/conf.d}"
  mkdir -p "$nginx_conf_dir"
  _ensure_f2b_geo "$nginx_conf_dir"

  # www.<domain> on the port-80 block too, when the site opted in: the ACME challenge
  # for the www SAN is answered here, and it must not fall through to default.conf.
  local www_names
  www_names="$(_www_server_name_suffix "$site_domain")"

  # Read the mode BEFORE the write, so replacing a vhost an operator tightened to 600
  # does not silently widen it back to 644. New file -> 644. See nginx_conf_perms.sh.
  local conf_file="$nginx_conf_dir/${site_domain}.conf" conf_mode
  conf_mode="$(_conf_target_mode "$conf_file")"

  log "Writing HTTP-only nginx config for $site_domain (proxy → $proxy_target)"
  cat >"$conf_file" <<EOF
# ${site_domain} — JStack site config (HTTP only; HTTPS added after cert acquisition)
server {
    listen 80;
    server_name ${site_domain}${www_names};

    # watchman 2026-09-16 (#906): layer-7 fail2ban ban. This block proxies to the app
    # until the cert exists, so an unguarded one lets a banned IP reach the backend.
    if (\$f2b_banned) { return 403; }

    # watchman 2026-09-08 (#868): resolve the upstream lazily at REQUEST time. A
    # parse-time hostname makes nginx refuse to START whenever the named container is
    # not yet up, which takes down EVERY vhost, not just this one.
    # See PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams.
    resolver 127.0.0.11 valid=10s ipv6=off;

    location /.well-known/acme-challenge/ {
        alias /var/www/certbot/.well-known/acme-challenge/;
    }

    location / {
        set \$upstream_site ${proxy_target};
        proxy_pass \$upstream_site;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
  _match_conf_dir_perms "$nginx_conf_dir" "$conf_file" "$conf_mode"
}

install_site_ssl_certificate() {
  local site_domain="$1"
  if [ -z "$site_domain" ]; then
    log "ERROR: install_site_ssl_certificate requires domain"
    return 1
  fi

  log "Acquiring Let's Encrypt certificate for $site_domain..."

  local CHALLENGE_DIR="$REPO_ROOT/nginx/certbot/www/.well-known/acme-challenge"
  mkdir -p "$CHALLENGE_DIR"
  chmod -R 755 "$REPO_ROOT/nginx/certbot/www"

  local email_arg="--email $EMAIL"
  if [ -z "$EMAIL" ] || [ "$EMAIL" = "admin@example.com" ]; then
    email_arg="--register-unsafely-without-email"
    log "⚠ No real email configured — using unsafe registration"
  fi

  if docker compose -f "$REPO_ROOT/docker-compose.yml" run --rm --entrypoint="" certbot \
    certbot certonly --webroot -w /var/www/certbot $email_arg \
    -d "$site_domain" --rsa-key-size 2048 --agree-tos --non-interactive >/dev/null 2>&1; then
    log "✓ Certificate acquired for $site_domain"
    return 0
  else
    log "⚠ Failed to acquire certificate for $site_domain"
    log "  Verify DNS for $site_domain points to this server and retry."
    return 1
  fi
}

upgrade_site_to_https() {
  local site_domain="$1"
  local site_port="$2"
  local site_container="$3"

  if [ -z "$site_domain" ] || [ -z "$site_port" ]; then
    log "ERROR: upgrade_site_to_https requires domain and port"
    return 1
  fi

  local site_profile
  site_profile="$(_site_profile "$site_domain")"
  case "$site_profile" in
    standard|webhook) ;;
    connector)
      upgrade_connector_site_to_https "$site_domain" "$site_port" "$site_container"
      return
      ;;
    *)
      log "ERROR: unknown SITE_PROFILE '$site_profile' for $site_domain (want: standard|webhook|connector)"
      return 1
      ;;
  esac

  # Resolved BEFORE the cert check and before the write: a bad SITE_XFRAME or a CSP
  # extra on a webhook must abort with a message, not write half a vhost.
  local site_xframe site_csp
  site_xframe="$(_site_xframe "$site_domain")" || return 1
  site_csp="$(_site_csp_value "$site_domain" "$site_profile")" || return 1

  local cert_dir="$REPO_ROOT/nginx/certbot/conf/live/${site_domain}"
  if [ ! -f "$cert_dir/fullchain.pem" ] || [ ! -f "$cert_dir/privkey.pem" ]; then
    log "⚠ No cert found for $site_domain — leaving HTTP-only"
    return 1
  fi

  local proxy_target
  proxy_target=$(_proxy_target "$site_port" "$site_container")
  local nginx_conf_dir="${NGINX_CONF_DIR:-$REPO_ROOT/nginx/conf.d}"
  _ensure_f2b_geo "$nginx_conf_dir"

  # www.<domain>, when the site opted in: the extra port-80 name, and the 301 block.
  # Both empty otherwise, and the output is then byte-for-byte what it was before.
  local www_names www_block
  www_names="$(_www_server_name_suffix "$site_domain")"
  www_block="$(_www_redirect_block "$site_domain" \
    "ssl_certificate /etc/letsencrypt/live/${site_domain}/fullchain.pem;" \
    "ssl_certificate_key /etc/letsencrypt/live/${site_domain}/privkey.pem;")"
  if [ -n "$www_block" ]; then www_block="${www_block}"$'\n'; fi

  # Read the mode BEFORE the write, so replacing a vhost an operator tightened to 600
  # does not silently widen it back to 644. New file -> 644. See nginx_conf_perms.sh.
  local conf_file="$nginx_conf_dir/${site_domain}.conf" conf_mode
  conf_mode="$(_conf_target_mode "$conf_file")"

  log "Writing HTTPS config for $site_domain (proxy → $proxy_target)"
  cat >"$conf_file" <<EOF
# ${site_domain} — JStack site config (HTTPS)
server {
    listen 80;
    server_name ${site_domain}${www_names};

    # watchman 2026-09-16 (#906): layer-7 fail2ban ban. Without it a banned IP still
    # gets a 301 here (seen live: 3000 redirects served to a banned scanner).
    if (\$f2b_banned) { return 403; }

    location /.well-known/acme-challenge/ {
        alias /var/www/certbot/.well-known/acme-challenge/;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
${www_block}
server {
    listen 443 ssl;
    server_name ${site_domain};
    ssl_certificate /etc/letsencrypt/live/${site_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${site_domain}/privkey.pem;

    # 'always' is load-bearing: without it nginx drops these headers on every 4xx/5xx,
    # which is most scanner traffic. Matches the watchman 2026-06-19 hardened vhosts.
    add_header X-Frame-Options ${site_xframe} always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Report-only: observe violations in the browser console, then promote to an
    # enforcing Content-Security-Policy once the site is known clean.
    add_header Content-Security-Policy-Report-Only "${site_csp}" always;

    # watchman 2026-09-08 (#848): production JS source maps were being harvested
    # (multiple networks fetched a6dad97d9634a72d.js.map from apps.odysseyalive.com).
    # A .map file hands an attacker the unminified source of the bundle. Refuse them at
    # the proxy: a build that ships maps beside the bundle cannot leak them here, and no
    # rebuild is needed to close it. Emitted for EVERY site, not just the one where it
    # was noticed — every site behind this generator serves a bundled frontend or an API,
    # and neither has a route whose path legitimately ends in .map. A site that genuinely
    # needs to serve a source map is the moment to add a profile option, not before.
    location ~* \.map\$ {
        access_log off;
        return 404;
    }

    # watchman 2026-09-08 (#868): resolve the upstream lazily at REQUEST time. A
    # parse-time hostname makes nginx refuse to START whenever the named container is
    # not yet up, which takes down EVERY vhost, not just this one.
    # See PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams.
    resolver 127.0.0.11 valid=10s ipv6=off;

    # watchman 2026-09-08 (#840): per-IP request/connection cap. Requires the 'perip'
    # and 'conperip' zones declared in the http block of nginx/nginx.conf; they are,
    # and nothing under scripts/ regenerates that file. Sized ~7x above the measured
    # legitimate peak (43 req/min for one IP); burst absorbs a full page load.
    limit_req zone=perip burst=50 nodelay;
    limit_conn conperip 20;

    # watchman 2026-09-15 (#841): layer-7 fail2ban ban. Requires the geo \$f2b_banned
    # block in nginx/conf.d/00-f2b-geo.conf (traffic arrives via Cloudflare, so nft bans never match).
    if (\$f2b_banned) { return 403; }

    location / {
        set \$upstream_site ${proxy_target};
        proxy_pass \$upstream_site;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Promoted 2026-09-18 from nginx/conf.d/odysseyalive.com.conf:95-97, which was
        # the only vhost carrying them. NOT tunable and NOT apex-specific: nginx's
        # defaults are proxy_buffer_size 4k and proxy_buffers 8 4k, and a response whose
        # headers exceed 4k — a long Set-Cookie, a big middleware rewrite header — makes
        # nginx answer 502 with "upstream sent too big header while reading response
        # header from upstream". Every standard-profile site behind this generator is a
        # proxied Next.js app of the same shape, so the other four carry that 502
        # latently today. No security directive is weakened by a larger buffer and no
        # site would want the 4k default back, so there is no option to get wrong.
        proxy_buffer_size 32k;
        proxy_buffers 16 32k;
        proxy_busy_buffers_size 64k;
    }
}
EOF
  _match_conf_dir_perms "$nginx_conf_dir" "$conf_file" "$conf_mode"
}

# The `connector` profile: an MCP / SSE (Streamable-HTTP) endpoint fronting a claude.ai
# remote connector. Dispatched to from upgrade_site_to_https when SITE_PROFILE=connector.
#
# Why this is a separate emitter and not a flag on the standard heredoc: SSE and a normal
# website want OPPOSITE proxy settings. The standard block buffers, times out at 60s and
# sets `Connection "upgrade"`. On a long-lived SSE GET those three are fatal — the stream
# is withheld by the buffer, cut at 60s, and the hop-by-hop Connection header confuses a
# non-websocket streaming upstream. Almost every proxy line differs, so a shared emitter
# would be a conditional per line.
#
# What is NOT different: the hardening. Every add_header, the rate limits, the resolver
# and the $f2b_banned guard are the same contract as the standard profile, so
# check_vhost_hardening.sh and check_nginx_ban_guard.sh pass here too. Before 2026-09-18
# these two vhosts were maintained by two copies of sites/<domain>/patch-nginx-sse.sh and
# inherited nothing the generator gained: they were missing X-Frame-Options,
# X-XSS-Protection and a CSP header at the moment this profile was written.
#
# Optional inputs (exported before the call; the per-site .env options in the OPTIONS
# block at the top of this file apply here too):
#   connector_label  — the upstream project name for the header comment, e.g.
#                      "playwright-mcp". Cosmetic; defaults to "MCP".
#   ORIGIN_CERT=1    — serve a Cloudflare Origin Certificate from
#                      nginx/certbot/conf/cloudflare-origin/<domain>.{pem,key} instead of
#                      the Let's Encrypt cert. Carried over from patch-nginx-sse.sh so
#                      deleting that script loses no capability. Default 0 (Let's Encrypt).
upgrade_connector_site_to_https() {
  local site_domain="$1"
  local site_port="$2"
  local site_container="$3"
  local connector_label="${connector_label:-MCP}"
  local origin_cert="${ORIGIN_CERT:-0}"

  if [ -z "$site_domain" ] || [ -z "$site_port" ]; then
    log "ERROR: upgrade_connector_site_to_https requires domain and port"
    return 1
  fi

  # Same options and the same builders as the standard profile, resolved before any
  # write. A connector is a proxy-tuning variant, never a different security contract.
  local site_xframe site_csp
  site_xframe="$(_site_xframe "$site_domain")" || return 1
  site_csp="$(_site_csp_value "$site_domain" connector)" || return 1

  local cert_line key_line
  if [ "$origin_cert" = "1" ]; then
    local origin_dir="$REPO_ROOT/nginx/certbot/conf/cloudflare-origin"
    if [ ! -f "$origin_dir/${site_domain}.pem" ] || [ ! -f "$origin_dir/${site_domain}.key" ]; then
      log "⚠ ORIGIN_CERT=1 but no origin cert/key for $site_domain in $origin_dir — leaving config unchanged"
      return 1
    fi
    cert_line="ssl_certificate     /etc/letsencrypt/cloudflare-origin/${site_domain}.pem;"
    key_line="ssl_certificate_key /etc/letsencrypt/cloudflare-origin/${site_domain}.key;"
  else
    local cert_dir="$REPO_ROOT/nginx/certbot/conf/live/${site_domain}"
    if [ ! -f "$cert_dir/fullchain.pem" ] || [ ! -f "$cert_dir/privkey.pem" ]; then
      log "⚠ No cert found for $site_domain — leaving HTTP-only"
      return 1
    fi
    cert_line="ssl_certificate     /etc/letsencrypt/live/${site_domain}/fullchain.pem;"
    key_line="ssl_certificate_key /etc/letsencrypt/live/${site_domain}/privkey.pem;"
  fi

  local proxy_target
  proxy_target=$(_proxy_target "$site_port" "$site_container")
  local nginx_conf_dir="${NGINX_CONF_DIR:-$REPO_ROOT/nginx/conf.d}"
  mkdir -p "$nginx_conf_dir"
  _ensure_f2b_geo "$nginx_conf_dir"

  # www.<domain>, same opt-in as the standard profile. A connector is normally a
  # subdomain and will not set it; it is wired here so a site's shape never depends on
  # which proxy-tuning profile it picked.
  local www_names www_block
  www_names="$(_www_server_name_suffix "$site_domain")"
  www_block="$(_www_redirect_block "$site_domain" "$cert_line" "$key_line")"
  if [ -n "$www_block" ]; then www_block="${www_block}"$'\n'; fi

  # Read the mode BEFORE the write, so replacing a vhost an operator tightened to 600
  # does not silently widen it back to 644. New file -> 644. See nginx_conf_perms.sh.
  local conf_file="$nginx_conf_dir/${site_domain}.conf" conf_mode
  conf_mode="$(_conf_target_mode "$conf_file")"

  log "Writing HTTPS connector config for $site_domain (SSE, proxy → $proxy_target)"
  cat >"$conf_file" <<EOF
# ${site_domain} — ${connector_label} remote connector (claude.ai). SSE-tuned.
# JStack site config (HTTPS, connector profile). Generated by
# scripts/core/setup_service_subdomains_ssl.sh — edit the generator, not this file.
server {
    listen 80;
    server_name ${site_domain}${www_names};

    # watchman 2026-09-16 (#906): layer-7 fail2ban ban (see conf.d/00-f2b-geo.conf).
    if (\$f2b_banned) { return 403; }
    location /.well-known/acme-challenge/ {
        alias /var/www/certbot/.well-known/acme-challenge/;
    }
    location / { return 301 https://\$host\$request_uri; }
}
${www_block}
server {
    listen 443 ssl;
    http2 on;
    server_name ${site_domain};

    ${cert_line}
    ${key_line}

    server_tokens off;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "no-referrer" always;

    # watchman 2026-09-18 (#912): a connector vhost is a generated variant, not a
    # hardening exemption. These three were absent for as long as this file was
    # hand-maintained by patch-nginx-sse.sh. 'always' is load-bearing: without it nginx
    # drops the header on every 4xx/5xx, which is most scanner traffic.
    # Referrer-Policy stays "no-referrer" (the standard profile emits
    # strict-origin-when-cross-origin) — a connector URL can carry a session-scoped path
    # and there is no referrer this endpoint benefits from leaking.
    add_header X-Frame-Options ${site_xframe} always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Report-only, exactly as the standard profile: it observes and never blocks, so it
    # cannot break an OAuth consent page or a JSON/SSE response on this endpoint.
    add_header Content-Security-Policy-Report-Only "${site_csp}" always;

    # watchman 2026-09-08 (#848): refuse production JS source maps, same as the standard
    # profile. Hand-added to apps.odysseyalive.com after multiple networks were seen
    # fetching a6dad97d9634a72d.js.map, and emitted here too because a connector is a
    # proxy-tuning variant, never a hardening exemption. MCP Streamable-HTTP and SSE both
    # address a single endpoint path; neither has a route ending in .map to lose.
    location ~* \.map\$ {
        access_log off;
        return 404;
    }

    # Cloudflare real-IP trust is declared ONCE, at http level in nginx/nginx.conf
    # (all 22 ranges + real_ip_header CF-Connecting-IP, commit ab37d20), which covers
    # every server block including this one. Do NOT re-add the list here: two copies of
    # one list drift on the first Cloudflare range change, and the vhost copy wins.

    # OPTIONAL defense-in-depth — restrict inbound to Anthropic's published ranges.
    # Works on BOTH grey (direct source IP) and orange (restored via real_ip above).
    # Verify current ranges at https://platform.claude.com/docs/en/api/ip-addresses.
    #allow 160.79.104.0/21;
    #allow 2607:6bc0::/48;
    #deny all;

    # Streamable HTTP + SSE: unbuffered, long-lived GET stream.
    # watchman 2026-09-08 (#840): per-IP cap, sized ~7x above the measured
    # legitimate peak of 43 req/min. burst=50 nodelay absorbs a page load.
    # watchman 2026-09-08 (#868): resolve the upstream lazily at REQUEST time, not at
    # config-parse time. A parse-time hostname makes nginx fail to start whenever the
    # named container is not yet up - on 2026-09-08 that crash-looped nginx 9 times and
    # took EVERY vhost down for 57s during a docker daemon restart.
    # See PAT-2026-05-27-nginx-resolver-for-dynamic-upstreams.
    resolver 127.0.0.11 valid=10s ipv6=off;

    limit_req zone=perip burst=50 nodelay;
    limit_conn conperip 20;

    # watchman 2026-09-15 (#841): layer-7 fail2ban ban (see conf.d/00-f2b-geo.conf).
    if (\$f2b_banned) { return 403; }

    location / {
        set \$upstream_site ${proxy_target};
        proxy_pass \$upstream_site;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        # The header-buffer half of the standard profile's promotion (F3, 2026-09-18).
        # proxy_buffers and proxy_busy_buffers_size govern the BODY and nginx ignores
        # them while proxy_buffering is off, so they are deliberately not emitted here;
        # proxy_buffer_size still sizes the buffer the RESPONSE HEADER is read into, and
        # an OAuth redirect or a long Set-Cookie over 4k is a 502 without it.
        proxy_buffer_size 32k;
    }
}
EOF
  _match_conf_dir_perms "$nginx_conf_dir" "$conf_file" "$conf_mode"
}
