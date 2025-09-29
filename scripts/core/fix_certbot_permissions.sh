#!/bin/bash
# Fix Certbot Certificate Permissions
# This script fixes the common issue where certbot creates root-owned
# certificate files that the jarvis user cannot access

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

CERTBOT_CONF="./nginx/certbot/conf"

log "Fixing certbot certificate permissions..."

# Check if archive directory exists
if [ ! -d "$CERTBOT_CONF/archive" ]; then
  log "ERROR: Archive directory does not exist at $CERTBOT_CONF/archive"
  log "Certificates may not have been generated yet"
  exit 1
fi

# Use Docker container with root privileges to fix permissions
# This works without sudo since the user is in the docker group
log "Using Docker to fix certificate ownership and permissions..."
if docker run --rm -v "$(pwd)/nginx/certbot/conf:/etc/letsencrypt" alpine sh -c "chown -R 1000:1000 /etc/letsencrypt/archive /etc/letsencrypt/live /etc/letsencrypt/renewal 2>/dev/null && chmod -R 755 /etc/letsencrypt/archive /etc/letsencrypt/live /etc/letsencrypt/renewal 2>/dev/null"; then
  log "✓ Certificate ownership and permissions fixed via Docker"
else
  log "⚠ Docker-based fix failed, attempting sudo method..."

  # Fallback to sudo if Docker approach fails
  if sudo -n true 2>/dev/null; then
    sudo chown -R "${USER}:${USER}" "$CERTBOT_CONF/archive" "$CERTBOT_CONF/live" "$CERTBOT_CONF/renewal" 2>/dev/null || true
    sudo chmod -R 755 "$CERTBOT_CONF/archive" "$CERTBOT_CONF/live" "$CERTBOT_CONF/renewal" 2>/dev/null || true
    log "✓ Certificate permissions fixed via sudo"
  else
    log "ERROR: Both Docker and sudo methods failed"
    log "Please run: sudo chown -R $USER:$USER nginx/certbot/conf/{archive,live,renewal}"
    log "Then run: sudo chmod -R 755 nginx/certbot/conf/{archive,live,renewal}"
    exit 1
  fi
fi

# Verify certificates are now accessible
log "Verifying certificate accessibility..."
cert_count=0
for cert_dir in "$CERTBOT_CONF/live"/*; do
  if [ -d "$cert_dir" ]; then
    domain=$(basename "$cert_dir")
    if [ -f "$cert_dir/fullchain.pem" ]; then
      log "✓ Certificate accessible: $domain"
      cert_count=$((cert_count + 1))
    else
      log "⚠ Certificate not found: $domain"
    fi
  fi
done

if [ $cert_count -eq 0 ]; then
  log "⚠ No certificates found or accessible"
  exit 1
else
  log "✓ Successfully fixed permissions for $cert_count certificate(s)"
fi

log "Certificate permissions fixed successfully!"
log "You can now run: bash scripts/core/enable_https_redirects.sh"