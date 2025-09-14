#!/bin/bash
# JStack Dependency Configuration and Permission Fix Script
# Usage: configure_dependencies.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Docker group membership
if ! groups | grep -qw docker; then
  log "User $USER is not in the docker group. Adding..."
  sudo usermod -aG docker "$USER"
  log "User $USER added to docker group. You may need to log out and back in."
else
  log "User $USER is already in the docker group."
fi

WORKSPACE="$(dirname "$0")/../.."
# Fix permissions for workspace-managed directories
for DIR in "$WORKSPACE/data/supabase" "$WORKSPACE/data/n8n" "$WORKSPACE/data/chrome" "$WORKSPACE/nginx/conf.d" "$WORKSPACE/nginx/ssl" "$WORKSPACE/backups" "$WORKSPACE/logs"; do
  if [ -d "$DIR" ]; then
    # Validate DIR
    if [[ "$DIR" != $(realpath "$WORKSPACE"/*) ]]; then
      echo "Unsafe directory for chown/chmod. Aborting." >&2
      exit 2
    fi
    sudo chown -R "$USER:docker" "$DIR"
    sudo chmod -R 770 "$DIR"
    log "Permissions fixed for $DIR."
  fi
done

# NGINX config file
if [ -f "$WORKSPACE/nginx/nginx.conf" ]; then
  sudo chown "$USER:docker" "$WORKSPACE/nginx/nginx.conf"
  sudo chmod 664 "$WORKSPACE/nginx/nginx.conf"
  log "NGINX main config permissions set."
fi

# Certbot SSL directory
if [ -d "$WORKSPACE/nginx/ssl" ]; then
  sudo chown -R "$USER:docker" "$WORKSPACE/nginx/ssl"
  sudo chmod -R 770 "$WORKSPACE/nginx/ssl"
  log "Certbot SSL permissions set."
fi

log "Dependency configuration and permission fixes completed."
