#!/bin/bash
# JStack Full Stack Install Script
# Usage: full_stack_install.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting full stack installation..."

# Start Docker service if not running
if ! sudo systemctl is-active --quiet docker; then
  log "Starting Docker service..."
  sudo systemctl start docker
fi

# Start NGINX service if not running
if ! sudo systemctl is-active --quiet nginx; then
  log "Starting NGINX service..."
  sudo systemctl start nginx
fi

# Start Fail2ban service if not running
if ! sudo systemctl is-active --quiet fail2ban; then
  log "Starting Fail2ban service..."
  sudo systemctl start fail2ban
fi

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
  log "Deploying services via Docker Compose..."
  SUPABASE_USER="$SUPABASE_USER" SUPABASE_PASSWORD="$SUPABASE_PASSWORD" N8N_BASIC_AUTH_USER="$N8N_BASIC_AUTH_USER" N8N_BASIC_AUTH_PASSWORD="$N8N_BASIC_AUTH_PASSWORD" docker-compose -f "$COMPOSE_FILE" up -d
  log "Services deployed."
else
  log "docker-compose.yml not found at $COMPOSE_FILE."
fi

log "Full stack installation completed."
