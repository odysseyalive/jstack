#!/bin/bash
# JStack Full Stack Install Script
# Usage: full_stack_install.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_service_and_start() {
  SERVICE="$1"
  if ! sudo systemctl is-active --quiet "$SERVICE"; then
    log "Starting $SERVICE service..."
    if sudo systemctl start "$SERVICE"; then
      log "$SERVICE started successfully."
    else
      log "Warning: Failed to start $SERVICE. Please check service status manually."
    fi
  else
    log "$SERVICE service is already running."
  fi
}

check_docker_permissions() {
  if ! docker ps >/dev/null 2>&1; then
    log "Error: Cannot access Docker. Ensure:"
    log "  1. Docker service is running: sudo systemctl status docker"
    log "  2. User is in docker group: groups | grep docker"
    log "  3. If recently added to docker group, log out and back in or run: newgrp docker"
    exit 1
  fi
}

log "Starting full stack installation..."

# Check if user can use sudo for service management
if ! sudo -n true 2>/dev/null; then
  log "Warning: No sudo access detected. Some services may need manual starting."
  log "Please ensure Docker service is running."
else
  # Start Docker service if not running
  check_service_and_start "docker"
fi

# Check Docker permissions
check_docker_permissions

COMPOSE_FILE="$(dirname "$0")/../../docker-compose.yml"
log "Checking workspace volume directories..."
for DIR in "$(dirname "$0")/../../data/supabase" "$(dirname "$0")/../../data/n8n" "$(dirname "$0")/../../data/chrome" "$(dirname "$0")/../../nginx/conf.d" "$(dirname "$0")/../../nginx/ssl"; do
  if [ ! -d "$DIR" ]; then
    log "Creating missing directory: $DIR"
    mkdir -p "$DIR"
  fi
done
if [ -f "$COMPOSE_FILE" ]; then
  log "Prompting for required secrets..."
  # Prompt for N8N and Supabase credentials if not set
  if [ -z "$SUPABASE_USER" ]; then
    read -r -p "Enter Supabase DB username: " SUPABASE_USER
  fi
  if [ -z "$SUPABASE_PASSWORD" ]; then
    read -r -s -p "Enter Supabase DB password: " SUPABASE_PASSWORD; echo
  fi
  if [ -z "$N8N_BASIC_AUTH_USER" ]; then
    read -r -p "Enter n8n admin username: " N8N_BASIC_AUTH_USER
  fi
  if [ -z "$N8N_BASIC_AUTH_PASSWORD" ]; then
    read -r -s -p "Enter n8n admin password: " N8N_BASIC_AUTH_PASSWORD; echo
  fi
  log "Generating default SSL certificate for nginx..."
  bash "$(dirname "$0")/ssl_cert.sh" generate_self_signed "default" "admin@localhost"
  log "Deploying services via Docker Compose..."
  SUPABASE_USER="$SUPABASE_USER" SUPABASE_PASSWORD="$SUPABASE_PASSWORD" N8N_BASIC_AUTH_USER="$N8N_BASIC_AUTH_USER" N8N_BASIC_AUTH_PASSWORD="$N8N_BASIC_AUTH_PASSWORD" docker-compose -f "$COMPOSE_FILE" up -d
  log "Services deployed."
else
  log "docker-compose.yml not found at $COMPOSE_FILE."
fi

log "Full stack installation completed."
