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

# Files written here must match the ownership and mode of the rest of conf.d (the stack
# operator's account, 644). A root run would otherwise leave root-owned files that the
# operator cannot edit.
_match_conf_dir_perms() {
  local nginx_conf_dir="$1" file="$2"
  chmod 644 "$file"
  if [ "$(id -u)" -eq 0 ]; then chown --reference="$nginx_conf_dir" "$file"; fi
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
  local nginx_conf_dir="$REPO_ROOT/nginx/conf.d"
  mkdir -p "$nginx_conf_dir"
  _ensure_f2b_geo "$nginx_conf_dir"

  log "Writing HTTP-only nginx config for $site_domain (proxy → $proxy_target)"
  cat >"$nginx_conf_dir/${site_domain}.conf" <<EOF
# ${site_domain} — JStack site config (HTTP only; HTTPS added after cert acquisition)
server {
    listen 80;
    server_name ${site_domain};

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
  _match_conf_dir_perms "$nginx_conf_dir" "$nginx_conf_dir/${site_domain}.conf"
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
  # watchman 2026-09-08 (#833): extra origins for the CSP connect-src directive, e.g.
  # "https://foohook.example.com wss://foohook.example.com" for a site that talks to a
  # Convex/websocket backend on its own subdomain. Export or set it before calling;
  # defaults to empty, which leaves connect-src at 'self' only.
  local csp_connect_extra="${csp_connect_extra:-}"

  if [ -z "$site_domain" ] || [ -z "$site_port" ]; then
    log "ERROR: upgrade_site_to_https requires domain and port"
    return 1
  fi

  local cert_dir="$REPO_ROOT/nginx/certbot/conf/live/${site_domain}"
  if [ ! -f "$cert_dir/fullchain.pem" ] || [ ! -f "$cert_dir/privkey.pem" ]; then
    log "⚠ No cert found for $site_domain — leaving HTTP-only"
    return 1
  fi

  local proxy_target
  proxy_target=$(_proxy_target "$site_port" "$site_container")
  local nginx_conf_dir="$REPO_ROOT/nginx/conf.d"
  _ensure_f2b_geo "$nginx_conf_dir"

  log "Writing HTTPS config for $site_domain (proxy → $proxy_target)"
  cat >"$nginx_conf_dir/${site_domain}.conf" <<EOF
# ${site_domain} — JStack site config (HTTPS)
server {
    listen 80;
    server_name ${site_domain};

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

server {
    listen 443 ssl;
    server_name ${site_domain};
    ssl_certificate /etc/letsencrypt/live/${site_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${site_domain}/privkey.pem;

    # 'always' is load-bearing: without it nginx drops these headers on every 4xx/5xx,
    # which is most scanner traffic. Matches the watchman 2026-06-19 hardened vhosts.
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Report-only: observe violations in the browser console, then promote to an
    # enforcing Content-Security-Policy once the site is known clean.
    add_header Content-Security-Policy-Report-Only "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'${csp_connect_extra:+ $csp_connect_extra}; frame-ancestors 'self'; base-uri 'self'; form-action 'self'" always;

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
    }
}
EOF
  _match_conf_dir_perms "$nginx_conf_dir" "$nginx_conf_dir/${site_domain}.conf"
}
