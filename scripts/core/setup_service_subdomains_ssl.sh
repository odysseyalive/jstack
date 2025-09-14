#!/bin/bash
# JStack Service Subdomains SSL Setup Script
# Usage: setup_service_subdomains_ssl.sh

set -e

# Load configuration
source jstack.config.default 2>/dev/null || true

# Extract domain from config
DOMAIN="${DOMAIN:-example.com}"
EMAIL="${EMAIL:-admin@example.com}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Service subdomains from config
SERVICE_SUBDOMAINS=(
  "api.${DOMAIN}"
  "studio.${DOMAIN}"
  "n8n.${DOMAIN}"
  "chrome.${DOMAIN}"
)

log "Setting up SSL certificates for service subdomains..."

# Create SSL directories
mkdir -p nginx/ssl/live nginx/ssl/work nginx/ssl/logs

for SUBDOMAIN in "${SERVICE_SUBDOMAINS[@]}"; do
  log "Setting up SSL for $SUBDOMAIN..."
  
  # Create directory for this domain
  mkdir -p "nginx/ssl/live/$SUBDOMAIN"
  
  # Check if certificates already exist
  if [ -f "nginx/ssl/live/$SUBDOMAIN/fullchain.pem" ] && [ -f "nginx/ssl/live/$SUBDOMAIN/privkey.pem" ]; then
    log "SSL certificates already exist for $SUBDOMAIN, skipping..."
    continue
  fi
  
  # Try Let's Encrypt first (will fail if domain doesn't resolve)
  if command -v certbot >/dev/null 2>&1; then
    log "Attempting Let's Encrypt certificate for $SUBDOMAIN..."
    if certbot certonly --standalone \
      --non-interactive \
      --agree-tos \
      --email "$EMAIL" \
      --domains "$SUBDOMAIN" \
      --config-dir ./nginx/ssl \
      --work-dir ./nginx/ssl/work \
      --logs-dir ./nginx/ssl/logs \
      --http-01-port 80 \
      2>/dev/null; then
      log "✓ Let's Encrypt certificate obtained for $SUBDOMAIN"
      continue
    else
      log "⚠ Let's Encrypt failed for $SUBDOMAIN, generating self-signed certificate..."
    fi
  fi
  
  # Generate self-signed certificate as fallback
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "nginx/ssl/live/$SUBDOMAIN/privkey.pem" \
    -out "nginx/ssl/live/$SUBDOMAIN/fullchain.pem" \
    -subj "/C=${SSL_COUNTRY:-US}/ST=${SSL_STATE:-State}/L=${SSL_CITY:-City}/O=${SSL_ORGANIZATION:-Organization}/OU=${SSL_ORG_UNIT:-IT}/CN=$SUBDOMAIN" \
    2>/dev/null
  
  log "✓ Self-signed certificate generated for $SUBDOMAIN"
done

# Set proper permissions
find nginx/ssl -name "*.pem" -exec chmod 600 {} \;
find nginx/ssl -type d -exec chmod 700 {} \;

log "✓ SSL certificate setup completed for all service subdomains"

# Update NGINX config files with actual domain
if [ "$DOMAIN" != "example.com" ]; then
  log "Updating NGINX configs with domain: $DOMAIN"
  for conf_file in nginx/conf.d/*.example.com.conf; do
    if [ -f "$conf_file" ]; then
      # Extract service name from filename
      service_name=$(basename "$conf_file" .example.com.conf)
      new_conf_file="nginx/conf.d/${service_name}.${DOMAIN}.conf"
      
      # Replace example.com with actual domain
      sed "s/example\.com/${DOMAIN}/g" "$conf_file" > "$new_conf_file"
      rm "$conf_file"
      log "✓ Updated $service_name config for $DOMAIN"
    fi
  done
fi

log "✓ Service subdomain SSL setup complete"