#!/bin/bash
# JStack Core Install Script
# Installs nginx + certbot and acquires a Let's Encrypt cert for the base domain.
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

log "Starting core stack installation (nginx + certbot)..."

# Check if user can use sudo for service management
if ! sudo -n true 2>/dev/null; then
  log "Warning: No sudo access detected. Some services may need manual starting."
  log "Please ensure Docker service is running."
else
  check_service_and_start "docker"
fi

check_docker_permissions

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"

log "Checking core volume directories..."
for DIR in "$REPO_ROOT/nginx/conf.d" "$REPO_ROOT/nginx/ssl" "$REPO_ROOT/nginx/logs"; do
  if [ ! -d "$DIR" ]; then
    log "Creating missing directory: $DIR"
    mkdir -p "$DIR"
  fi
done

# Create certbot directories with proper permissions before Docker creates them
log "Setting up certbot directories..."
CERTBOT_WWW="$REPO_ROOT/nginx/certbot/www"
CERTBOT_CHALLENGE="$CERTBOT_WWW/.well-known/acme-challenge"
mkdir -p "$CERTBOT_CHALLENGE"
chmod -R 755 "$CERTBOT_WWW"
log "✓ Certbot challenge directory created with proper permissions"

# Create nginx logs directory with proper permissions
log "Setting up nginx logs directory..."
NGINX_LOGS="$REPO_ROOT/nginx/logs"
mkdir -p "$NGINX_LOGS"
chmod 755 "$NGINX_LOGS"
log "✓ Nginx logs directory created with proper permissions"

if [ ! -f "$COMPOSE_FILE" ]; then
  log "ERROR: $COMPOSE_FILE not found"
  exit 1
fi

log "Setting up configuration..."
CONFIG_FILE="$REPO_ROOT/jstack.config"
CONFIG_DEFAULT="$REPO_ROOT/jstack.config.default"

if [ ! -f "$CONFIG_FILE" ]; then
  log "Creating user configuration file..."
  cp "$CONFIG_DEFAULT" "$CONFIG_FILE"

  echo ""
  echo "Domain Configuration:"
  echo "Please enter your domain name (e.g., mydomain.com)"
  echo "This will be used for the Let's Encrypt cert for the base site."
  echo ""

  read -r -p "Enter your domain name [example.com]: " USER_DOMAIN
  USER_DOMAIN=${USER_DOMAIN:-example.com}

  read -r -p "Enter your email for SSL certificates [admin@${USER_DOMAIN}]: " USER_EMAIL
  USER_EMAIL=${USER_EMAIL:-admin@${USER_DOMAIN}}

  sed -i "s/DOMAIN=\"example.com\"/DOMAIN=\"${USER_DOMAIN}\"/" "$CONFIG_FILE"
  sed -i "s/EMAIL=\"admin@example.com\"/EMAIL=\"${USER_EMAIL}\"/" "$CONFIG_FILE"

  log "✓ Configuration saved to jstack.config"
  log "✓ Domain: $USER_DOMAIN"
  log "✓ Email: $USER_EMAIL"
else
  log "Using existing configuration file: $CONFIG_FILE"
fi

# Load the configuration
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Update .env with core variables
ENV_FILE="$REPO_ROOT/.env"
touch "$ENV_FILE"

if [ -n "$EMAIL" ]; then
  sed -i "/^EMAIL=/d" "$ENV_FILE" 2>/dev/null || true
  echo "EMAIL=$EMAIL" >>"$ENV_FILE"
fi
if [ -n "$DOMAIN" ]; then
  sed -i "/^DOMAIN=/d" "$ENV_FILE" 2>/dev/null || true
  echo "DOMAIN=$DOMAIN" >>"$ENV_FILE"
fi

log "Bringing up core services (nginx + certbot)..."
run_docker_command docker compose -f "$COMPOSE_FILE" up -d
log "✓ Core services up"

# Acquire base-domain certificate (apex). Service subdomains acquire their own
# certs when their installers run.
acquire_base_cert() {
  local subdomain="$1"
  log "Acquiring certificate for $subdomain..."

  if command -v dig >/dev/null 2>&1; then
    if dig +short "$subdomain" A | grep -q .; then
      log "✓ $subdomain resolves"
    else
      log "⚠ $subdomain does not resolve - certificate acquisition will likely fail"
    fi
  fi

  local email_arg="--email $EMAIL"
  if [[ -z "$EMAIL" || "$EMAIL" == "admin@example.com" ]]; then
    email_arg="--register-unsafely-without-email"
    log "⚠ No email configured, using unsafe registration for $subdomain"
  fi

  docker compose -f "$COMPOSE_FILE" run --rm --entrypoint="" certbot \
    certbot certonly --webroot -w /var/www/certbot $email_arg \
    -d "$subdomain" --rsa-key-size 2048 --agree-tos || \
    log "⚠ Failed to acquire certificate for $subdomain (you can retry later)"
}

if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "example.com" ]; then
  CHALLENGE_DIR="$REPO_ROOT/nginx/certbot/www/.well-known/acme-challenge"
  mkdir -p "$CHALLENGE_DIR"
  chmod -R 755 "$REPO_ROOT/nginx/certbot/www"
  acquire_base_cert "$DOMAIN"
fi

# Fix certificate file permissions
log "Fixing certificate file permissions..."
docker run --rm -v "$REPO_ROOT/nginx/certbot/conf:/etc/letsencrypt" alpine sh -c \
  "chown -R 1000:1000 /etc/letsencrypt/archive /etc/letsencrypt/live /etc/letsencrypt/renewal 2>/dev/null || true; \
   chmod -R 755 /etc/letsencrypt/archive /etc/letsencrypt/live /etc/letsencrypt/renewal 2>/dev/null || true" \
  >/dev/null 2>&1 || log "⚠ Failed to fix cert permissions (run scripts/core/fix_certbot_permissions.sh manually if needed)"

# Reload nginx
log "Reloading nginx..."
if docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -s reload >/dev/null 2>&1; then
  log "✓ Nginx reloaded"
else
  log "⚠ Failed to reload nginx, restarting..."
  docker compose -f "$COMPOSE_FILE" restart nginx >/dev/null 2>&1 || true
fi

# Setup fail2ban for SSH and NGINX protection
log "Setting up fail2ban for SSH and NGINX protection..."
if bash "$(dirname "$0")/setup_fail2ban.sh"; then
  log "✓ Fail2ban setup completed"
else
  log "⚠ Fail2ban setup encountered issues - check logs above"
fi

# Setup log rotation
log "Setting up log rotation..."
if bash "$(dirname "$0")/setup_log_rotation.sh"; then
  log "✓ Log rotation setup completed"
else
  log "⚠ Log rotation setup encountered issues - check logs above"
fi

log "Core installation complete."
echo ""
echo "Next step: deploy a site"
echo "  bash jstack.sh --install-site sites/<your-domain>"
echo ""
