#!/bin/bash
# JStack Conflict Detection Script
# Usage: detect_conflicts.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check for port conflicts
PORTS=(443 5432 5678 3000 4000)
for PORT in "${PORTS[@]}"; do
  if lsof -i :$PORT | grep LISTEN; then
    log "Port $PORT is already in use."
  else
    log "Port $PORT is available."
  fi
done

# Check for Docker Compose file conflicts
if [ -f "docker-compose.yml" ]; then
  log "docker-compose.yml exists."
else
  log "docker-compose.yml not found."
fi

# Check for NGINX config conflicts
NGINX_CONF="nginx.conf"
if grep -q "server_name" "$NGINX_CONF"; then
  log "NGINX config contains server_name entries."
else
  log "No server_name entries found in NGINX config."
fi

# Check for running services
SERVICES=(nginx docker fail2ban)
for SERVICE in "${SERVICES[@]}"; do
  if sudo systemctl is-active --quiet "$SERVICE"; then
    log "$SERVICE is running."
  else
    log "$SERVICE is not running."
  fi
done

log "Conflict detection completed."
