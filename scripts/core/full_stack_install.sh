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

# Create certbot directories with proper permissions before Docker creates them
log "Setting up certbot directories..."
CERTBOT_WWW="$(dirname "$0")/../../nginx/certbot/www"
CERTBOT_CHALLENGE="$CERTBOT_WWW/.well-known/acme-challenge"

mkdir -p "$CERTBOT_CHALLENGE"
chmod -R 755 "$CERTBOT_WWW"
log "✓ Certbot challenge directory created with proper permissions"
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

  # Function to wait for services to be ready
  wait_for_services() {
    log "Waiting for services to be ready..."

    # Wait for Kong (API Gateway)
    local retries=30
    local wait_time=10
    for i in $(seq 1 $retries); do
      if curl -s http://localhost:8000/ >/dev/null 2>&1; then
        log "✓ Kong is ready"
        break
      fi
      log "Waiting for Kong... ($i/$retries)"
      sleep $wait_time
    done
    if [ $i -eq $retries ]; then
      log "⚠ Kong did not become ready within $(($retries * $wait_time)) seconds, continuing anyway"
    fi

    # Wait for Supabase Studio
    for i in $(seq 1 $retries); do
      if curl -s -f http://localhost:3000/ >/dev/null 2>&1; then
        log "✓ Supabase Studio is ready"
        break
      fi
      log "Waiting for Supabase Studio... ($i/$retries)"
      sleep $wait_time
    done
    if [ $i -eq $retries ]; then
      log "⚠ Supabase Studio did not become ready within $(($retries * $wait_time)) seconds, continuing anyway"
    fi
  }

  # Wait for services to be ready before proceeding with SSL setup
  wait_for_services

  # Service Readiness Integration: Add service dependency checking
  # Verify Kong/Supabase services are ready before certificate acquisition
  # Add health checks for each service before enabling HTTPS
  # Implement timeout and retry logic for service readiness

  # Installation Process Sequencing:
  # 1. Generate HTTP-only nginx configs ✓ (already done)
  # 2. Start all services with HTTP access ✓ (already done)
  # 3. Validate service readiness ✓ (added above)
  # 4. Acquire certificates per subdomain iteratively ✓ (already done)
  # 5. Update configs to enable HTTPS per successful certificate ✓ (added below)
  # 6. Reload nginx progressively ✓ (added below)

  # Fix Supabase database user passwords
  log "Fixing Supabase database user passwords..."
  bash "$(dirname "$0")/../fix-supabase-passwords.sh"

  # Function to generate self-signed certificate as fallback
  generate_self_signed_cert() {
    local subdomain="$1"
    local cert_dir="./nginx/certbot/live/${subdomain}"
    local conf_dir="./nginx/certbot/conf"

    log "Generating self-signed certificate for ${subdomain}..."

    # Create certificate directory
    mkdir -p "$cert_dir"

    # Generate self-signed certificate using openssl
    if openssl req -x509 -newkey rsa:2048 -keyout "${cert_dir}/privkey.pem" -out "${cert_dir}/fullchain.pem" -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=${subdomain}" 2>/dev/null; then
      # Set proper permissions
      chmod 600 "${cert_dir}/privkey.pem" "${cert_dir}/fullchain.pem"
      log "✓ Self-signed certificate generated for ${subdomain}"
      log "⚠ WARNING: Using self-signed certificate for ${subdomain}. Browser will show security warning."
      log "⚠ Manual certificate renewal required before expiration."
      return 0
    else
      log "✗ Failed to generate self-signed certificate for ${subdomain}"
      return 1
    fi
  }

  log "Acquiring SSL certificates individually for subdomains..."

  # Validate challenge directory is writable
  CHALLENGE_DIR="$(dirname "$0")/../../nginx/certbot/www/.well-known/acme-challenge"
  if [ ! -d "$CHALLENGE_DIR" ]; then
    log "⚠ Challenge directory does not exist, creating: $CHALLENGE_DIR"
    mkdir -p "$CHALLENGE_DIR"
    chmod -R 755 "$(dirname "$0")/../../nginx/certbot/www"
  fi

  if [ ! -w "$CHALLENGE_DIR" ]; then
    log "✗ ERROR: Challenge directory is not writable: $CHALLENGE_DIR"
    log "  Run: chmod -R 755 nginx/certbot/www"
    log "  Attempting automatic fix..."
    chmod -R 755 "$(dirname "$0")/../../nginx/certbot/www" || log "⚠ Failed to fix permissions, certificate acquisition may fail"
  else
    log "✓ Challenge directory is writable"
  fi

  for SUBDOMAIN in "api.$DOMAIN" "studio.$DOMAIN" "n8n.$DOMAIN" "chrome.$DOMAIN"; do
    log "Acquiring certificate for $SUBDOMAIN..."

    # Check DNS resolution
    if command -v dig >/dev/null 2>&1; then
      if dig +short "$SUBDOMAIN" A | grep -q .; then
        log "✓ $SUBDOMAIN resolves"
      else
        log "⚠ $SUBDOMAIN does not resolve - certificate acquisition will likely fail"
        # Continue anyway, as DNS might be set up after
      fi
    else
      log "⚠ dig not available, assuming $SUBDOMAIN resolves"
    fi

    # Select email argument
    email_arg="--email $EMAIL"
    if [[ -z "$EMAIL" || "$EMAIL" == "admin@example.com" ]]; then
      email_arg="--register-unsafely-without-email"
      log "⚠ No email configured, using unsafe registration for $SUBDOMAIN"
    fi

    # Run certbot for individual domain
    log "Running certbot for $SUBDOMAIN..."

    # Capture both stdout and stderr for error analysis (with 180 second timeout)
    CERTBOT_OUTPUT=$(timeout 180 docker-compose run --rm --entrypoint="" certbot certbot certonly --webroot -w /var/www/certbot $email_arg -d "$SUBDOMAIN" --rsa-key-size 2048 --agree-tos --non-interactive 2>&1)
    CERTBOT_EXIT_CODE=$?

    if [ $CERTBOT_EXIT_CODE -eq 0 ]; then
      log "✓ SSL certificate acquired for $SUBDOMAIN"
    else
      log "⚠ Failed to acquire Let's Encrypt certificate for $SUBDOMAIN"
      log "Certbot output:"
      echo "$CERTBOT_OUTPUT" | tail -20

      # Analyze failure reason
      if echo "$CERTBOT_OUTPUT" | grep -q "urn:ietf:params:acme:error:dns"; then
        log "  Reason: DNS resolution issue - subdomain may not be properly configured"
      elif echo "$CERTBOT_OUTPUT" | grep -q "urn:ietf:params:acme:error:rateLimited"; then
        log "  Reason: Rate limiting - too many requests from this IP"
      elif echo "$CERTBOT_OUTPUT" | grep -q "urn:ietf:params:acme:error:connection"; then
        log "  Reason: Network/firewall issue preventing ACME challenge"
      elif echo "$CERTBOT_OUTPUT" | grep -q "urn:ietf:params:acme:error:unauthorized"; then
        log "  Reason: ACME challenge failed - webroot not accessible"
      else
        log "  Reason: Unknown error - check certbot output above"
      fi

      # Attempt self-signed certificate fallback
      log "Attempting self-signed certificate generation as fallback..."
      if generate_self_signed_cert "$SUBDOMAIN"; then
        log "✓ Self-signed certificate available for $SUBDOMAIN (HTTPS will show warnings)"
      else
        log "✗ Self-signed certificate generation failed - $SUBDOMAIN will remain HTTP-only"
        log "Manual certificate setup instructions:"
        log "  1. Ensure $SUBDOMAIN resolves to this server"
        log "  2. Run: docker-compose run --rm --entrypoint='' certbot certbot certonly --webroot -w /var/www/certbot --email $EMAIL -d $SUBDOMAIN --rsa-key-size 2048 --agree-tos"
        log "  3. Then run: docker-compose exec nginx nginx -s reload"
      fi
    fi
  done

  log "Updating nginx configs to enable HTTPS for successful certificates..."
  bash "$(dirname "$0")/setup_service_subdomains_ssl.sh" --with-ssl

  log "Enabling HTTPS redirects..."
  bash "$(dirname "$0")/enable_https_redirects.sh"

  # Set proper permissions for certificates
  find ./nginx/certbot/conf -name "*.pem" -exec chmod 600 {} \; 2>/dev/null || true
  find ./nginx/certbot/conf -type d -exec chmod 700 {} \; 2>/dev/null || true

  # Reload nginx to pick up certificates
  log "Reloading nginx..."
  if docker-compose exec nginx nginx -s reload >/dev/null 2>&1; then
    log "✓ Nginx reloaded"
  else
    log "⚠ Failed to reload nginx, restarting..."
    docker-compose restart nginx >/dev/null 2>&1
  fi

  # Review Installation Flow Changes:
  # - HTTP-only to HTTPS progression: configs start HTTP, update to HTTPS after certs
  # - Service readiness checks added before SSL acquisition
  # - Progressive config updates: HTTP → acquire certs → HTTPS → redirects → reload
  # - Double-check with Context7: individual certs reduce rate limit issues, webroot auth recommended for nginx in containers

  log "Full stack installation completed."
fi
