#!/bin/bash
# JStack Workspace Permission Fix Script
# Usage: fix_workspace_permissions.sh
# Ensures all workspace directories/files are owned by the deploying user and accessible to Docker containers.

set -e

WORKSPACE="$(dirname "$0")/../.."
USER_NAME="${USER:-$(whoami)}"
DOCKER_GROUP="docker"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Fixing permissions for all workspace directories..."

# Handle directories with regular user permissions (excluding Supabase which manages its own)
for DIR in "$WORKSPACE/data/n8n" "$WORKSPACE/data/chrome" "$WORKSPACE/nginx/conf.d" "$WORKSPACE/nginx/ssl" "$WORKSPACE/backups" "$WORKSPACE/logs"; do
  if [ -d "$DIR" ]; then
    # Validate DIR
    if [[ "$DIR" != $(realpath "$WORKSPACE"/*) ]]; then
      echo "Unsafe directory for chown/chmod. Aborting." >&2
      exit 2
    fi
    sudo chown -R "$USER_NAME:$DOCKER_GROUP" "$DIR"
    sudo chmod -R 770 "$DIR"
    log "Permissions fixed for $DIR."
  fi
done

# Fix certbot directory permissions to allow challenge file creation
if [ -d "$WORKSPACE/nginx/certbot/www" ]; then
  sudo chown -R "$USER_NAME:$DOCKER_GROUP" "$WORKSPACE/nginx/certbot/www"
  sudo chmod -R 755 "$WORKSPACE/nginx/certbot/www"
  log "Certbot webroot permissions fixed for challenge file access."
fi

# Ensure challenge directory exists with proper permissions
if [ ! -d "$WORKSPACE/nginx/certbot/www/.well-known/acme-challenge" ]; then
  mkdir -p "$WORKSPACE/nginx/certbot/www/.well-known/acme-challenge"
  sudo chown -R "$USER_NAME:$DOCKER_GROUP" "$WORKSPACE/nginx/certbot/www"
  sudo chmod -R 755 "$WORKSPACE/nginx/certbot/www"
  log "Created certbot challenge directory with proper permissions."
fi

if [ -f "$WORKSPACE/nginx/nginx.conf" ]; then
  sudo chown "$USER_NAME:$DOCKER_GROUP" "$WORKSPACE/nginx/nginx.conf"
  sudo chmod 664 "$WORKSPACE/nginx/nginx.conf"
  log "NGINX main config permissions set."
fi

log "Workspace permission fix completed."
