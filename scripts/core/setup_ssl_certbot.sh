#!/bin/bash
# JStack Certbot SSL Setup Script
# Usage: setup_ssl_certbot.sh

set -e

SITE_DIR="sites"
EMAIL="$(grep -m1 EMAIL jstack.config.default | cut -d'=' -f2)"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Setting up SSL certificates with Certbot for all domains..."

for SITE in "$SITE_DIR"/*; do
  if [ -d "$SITE" ]; then
    DOMAIN=$(grep -m1 DOMAIN "$SITE/.env" | cut -d'=' -f2)
    if [ -n "$DOMAIN" ]; then
      log "Requesting SSL certificate for $DOMAIN..."
      sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --config-dir ./nginx/ssl --work-dir ./nginx/ssl --logs-dir ./nginx/ssl || log "Certbot failed for $DOMAIN."
    else
      log "Missing DOMAIN in $SITE/.env, skipping SSL setup."
    fi
  fi
done

chmod 600 ./nginx/ssl/*.key
log "SSL certificate setup completed."

log "Restarting Docker services to apply SSL certificates..."
if command -v docker-compose >/dev/null 2>&1; then
    docker-compose down
    docker-compose up -d
    log "✓ Docker services restarted successfully"
else
    log "ERROR: docker-compose not found, please restart services manually"
    exit 1
fi

