#!/bin/bash
# JStack NGINX Site Registration Script
# Usage: register_sites_nginx.sh

set -e

SITE_DIR="sites"
NGINX_CONF="nginx/conf.d"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Registering all sites in NGINX..."

for SITE in "$SITE_DIR"/*; do
  if [ -d "$SITE" ]; then
    CONFIG_FILE="$SITE/site.config"
    if [ -f "$CONFIG_FILE" ]; then
      DOMAIN=$(grep -m1 DOMAIN "$CONFIG_FILE" | cut -d'=' -f2)
      PORT=$(grep -m1 PORT "$CONFIG_FILE" | cut -d'=' -f2)
      PUBLIC_HTML=$(grep -m1 PUBLIC_HTML "$CONFIG_FILE" | cut -d'=' -f2)
      SITE_ROOT=$(grep -m1 SITE_ROOT "$CONFIG_FILE" | cut -d'=' -f2)
      # Input validation
      if [[ "$DOMAIN" =~ [^a-zA-Z0-9._-] ]] || [[ "$PORT" =~ [^0-9] ]]; then
        echo "Error: Unsafe DOMAIN or PORT value. Aborting." >&2
        exit 2
      fi
      if [ -n "$DOMAIN" ] && [ -n "$PORT" ]; then
        NGINX_ENTRY="server {\n    listen 443 ssl;\n    server_name $DOMAIN;\n    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;\n    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;\n    root /$SITE/$SITE_ROOT/$PUBLIC_HTML;\n    index index.php index.html;\n    location / {\n        try_files $uri $uri/ =404;\n    }\n}"
        echo -e "$NGINX_ENTRY" > "$NGINX_CONF/$DOMAIN.conf"
        log "Registered $DOMAIN with root /$SITE/$SITE_ROOT/$PUBLIC_HTML in NGINX."
      else
        log "Missing DOMAIN or PORT in $CONFIG_FILE, skipping."
      fi
    else
      log "Missing site.config in $SITE, skipping."
    fi
  fi
done

log "Reloading NGINX config..."
log "Reloading NGINX config in container..."
docker compose exec nginx nginx -s reload
log "NGINX config reloaded."
