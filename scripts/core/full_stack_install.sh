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
    log "Cannot access Docker directly. Checking if user is in docker group..."
    if groups | grep -q docker; then
      log "User is in docker group. You must log out and log back in (or reboot) before installing if you were just added to the docker group."
      return 0
    else
      log "Error: User is not in docker group. Run: sudo usermod -aG docker $USER, then log out/in or reboot, before running install again."
    fi
    log "Error: Cannot access Docker. Ensure:"
    log "  1. Docker service is running: sudo systemctl status docker"
    log "  2. User is in docker group: groups | grep docker"
    log "  3. If recently added to docker group, log out and back in or run: newgrp docker"
    exit 1
  fi
}

run_docker_command() {
  if [ "$USE_NEWGRP_DOCKER" = "1" ]; then
    newgrp docker -c "$*"
  else
    "$@"
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
  log "Generating secure secrets..."
  # Generate secrets for Supabase
  bash "$(dirname "$0")/generate_secrets.sh" --save-env

  # Source the generated environment file to get the variables
  SECRETS_FILE="$(dirname "$0")/../../.env.secrets"
  if [ -f "$SECRETS_FILE" ]; then
    source "$SECRETS_FILE"
  else
    log "Error: Failed to generate secrets file"
    exit 1
  fi

  log "Setting up configuration..."

  # Create user config file if it doesn't exist
  CONFIG_FILE="$(dirname "$0")/../../jstack.config"
  CONFIG_DEFAULT="$(dirname "$0")/../../jstack.config.default"

  if [ ! -f "$CONFIG_FILE" ]; then
    log "Creating user configuration file..."
    cp "$CONFIG_DEFAULT" "$CONFIG_FILE"

    # Prompt for domain configuration
    echo ""
    echo "Domain Configuration:"
    echo "Please enter your domain name (e.g., mydomain.com)"
    echo "This will be used for SSL certificates and subdomain configuration."
    echo "Subdomains will be: api.DOMAIN, studio.DOMAIN, n8n.DOMAIN, chrome.DOMAIN"
    echo ""

    read -r -p "Enter your domain name [example.com]: " USER_DOMAIN
    USER_DOMAIN=${USER_DOMAIN:-example.com}

    read -r -p "Enter your email for SSL certificates [admin@${USER_DOMAIN}]: " USER_EMAIL
    USER_EMAIL=${USER_EMAIL:-admin@${USER_DOMAIN}}

    # Update the config file with user values
    sed -i "s/DOMAIN=\"example.com\"/DOMAIN=\"${USER_DOMAIN}\"/" "$CONFIG_FILE"
    sed -i "s/EMAIL=\"admin@example.com\"/EMAIL=\"${USER_EMAIL}\"/" "$CONFIG_FILE"

    # Update service URLs in config
    sed -i "s/n8n.example.com/n8n.${USER_DOMAIN}/" "$CONFIG_FILE"
    sed -i "s/api.example.com/api.${USER_DOMAIN}/" "$CONFIG_FILE"
    sed -i "s/studio.example.com/studio.${USER_DOMAIN}/" "$CONFIG_FILE"
    sed -i "s/chrome.example.com/chrome.${USER_DOMAIN}/" "$CONFIG_FILE"

    log "✓ Configuration saved to jstack.config"
    log "✓ Domain: $USER_DOMAIN"
    log "✓ Email: $USER_EMAIL"
  else
    log "Using existing configuration file: $CONFIG_FILE"
  fi

  # Load the configuration
  source "$CONFIG_FILE"

  log "Prompting for required credentials..."
  # Always prompt for N8N and Supabase credentials, overwriting existing values
  read -r -p "Enter Supabase DB username [${SUPABASE_USER:-supabase_admin}]: " SUPABASE_USER_INPUT
  SUPABASE_USER=${SUPABASE_USER_INPUT:-${SUPABASE_USER:-supabase_admin}}

  read -r -s -p "Enter Supabase DB password: " SUPABASE_PASSWORD
  echo

  read -r -p "Enter n8n admin username [${N8N_BASIC_AUTH_USER:-admin}]: " N8N_USER_INPUT
  N8N_BASIC_AUTH_USER=${N8N_USER_INPUT:-${N8N_BASIC_AUTH_USER:-admin}}

  read -r -s -p "Enter n8n admin password: " N8N_BASIC_AUTH_PASSWORD
  echo

  # Generate htpasswd file for Studio authentication using Supabase credentials
  log "Creating Studio authentication credentials using Supabase credentials..."
  echo "$SUPABASE_USER:$(openssl passwd -apr1 "$SUPABASE_PASSWORD")" >"$(dirname "$0")/../../nginx/htpasswd"
  chmod 644 "$(dirname "$0")/../../nginx/htpasswd"
  log "✓ Studio authentication configured for user: $SUPABASE_USER"

  # Update .env file with domain and email configuration
  ENV_FILE="$(dirname "$0")/../../.env"

  # Add or update EMAIL variable
  if [ -n "$EMAIL" ]; then
    sed -i "/^EMAIL=/d" "$ENV_FILE" 2>/dev/null || true
    echo "EMAIL=$EMAIL" >>"$ENV_FILE"
  fi

  # Add or update DOMAIN variable
  if [ -n "$DOMAIN" ]; then
    sed -i "/^DOMAIN=/d" "$ENV_FILE" 2>/dev/null || true
    echo "DOMAIN=$DOMAIN" >>"$ENV_FILE"
  fi

  # Update .env file with user-provided password
  if [ -n "$SUPABASE_PASSWORD" ]; then
    sed -i "/^SUPABASE_PASSWORD=/d" "$(dirname "$0")/../../.env" 2>/dev/null || true
    echo "SUPABASE_PASSWORD=$SUPABASE_PASSWORD" >>"$(dirname "$0")/../../.env"

    sed -i "/^SUPABASE_PASSWORD=/d" "$(dirname "$0")/../../.env.secrets" 2>/dev/null || true
    echo "SUPABASE_PASSWORD=$SUPABASE_PASSWORD" >>"$(dirname "$0")/../../.env.secrets"
  fi


  log "Setting up SSL certificates for service subdomains..."
  bash "$(dirname "$0")/setup_service_subdomains_ssl.sh" --http-only

  # Deploy services first (without full nginx configs)
  log "Deploying services via Docker Compose..."
  SUPABASE_USER="$SUPABASE_USER" \
    SUPABASE_PASSWORD="$SUPABASE_PASSWORD" \
    SUPABASE_JWT_SECRET="$SUPABASE_JWT_SECRET" \
    SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY"
  # Fix potential Kong configuration directory issue
  KONG_YML_PATH="$(dirname "$0")/../../data/supabase/kong.yml"
  if [ -d "$KONG_YML_PATH" ]; then
    log "Removing problematic kong.yml directory: $KONG_YML_PATH"
    rm -rf "$KONG_YML_PATH"
  fi

  N8N_BASIC_AUTH_USER="$N8N_BASIC_AUTH_USER" \
    N8N_BASIC_AUTH_PASSWORD="$N8N_BASIC_AUTH_PASSWORD" \
    run_docker_command docker-compose -f "$COMPOSE_FILE" up -d
  log "Services deployed."

  # Fix Supabase database user passwords
  log "Fixing Supabase database user passwords..."
  bash "$(dirname "$0")/../fix-supabase-passwords.sh"


log "Full stack installation completed."
