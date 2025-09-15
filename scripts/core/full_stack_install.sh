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
  
  # Generate htpasswd file for Studio authentication  
  log "Creating Studio authentication credentials..."
  read -r -p "Enter username for Studio access: " STUDIO_USERNAME
  read -r -s -p "Enter password for Studio access: " STUDIO_PASSWORD; echo
  echo "$STUDIO_USERNAME:$(openssl passwd -apr1 "$STUDIO_PASSWORD")" > "$(dirname "$0")/../../nginx/htpasswd"
  chmod 644 "$(dirname "$0")/../../nginx/htpasswd"
  log "✓ Studio authentication configured for user: $STUDIO_USERNAME"
  
  # Update .env file with domain and email configuration
  ENV_FILE="$(dirname "$0")/../../.env"
  
  # Add or update EMAIL variable
  if [ -n "$EMAIL" ]; then
    sed -i "/^EMAIL=/d" "$ENV_FILE" 2>/dev/null || true
    echo "EMAIL=$EMAIL" >> "$ENV_FILE"
  fi
  
  # Add or update DOMAIN variable  
  if [ -n "$DOMAIN" ]; then
    sed -i "/^DOMAIN=/d" "$ENV_FILE" 2>/dev/null || true
    echo "DOMAIN=$DOMAIN" >> "$ENV_FILE"
  fi
  
  # Update .env file with user-provided password
  if [ -n "$SUPABASE_PASSWORD" ]; then
    sed -i "/^SUPABASE_PASSWORD=/d" "$(dirname "$0")/../../.env" 2>/dev/null || true
    echo "SUPABASE_PASSWORD=$SUPABASE_PASSWORD" >> "$(dirname "$0")/../../.env"
    
    sed -i "/^SUPABASE_PASSWORD=/d" "$(dirname "$0")/../../.env.secrets" 2>/dev/null || true
    echo "SUPABASE_PASSWORD=$SUPABASE_PASSWORD" >> "$(dirname "$0")/../../.env.secrets"
  fi
  
  log "Generating default SSL certificate for nginx..."
  bash "$(dirname "$0")/ssl_cert.sh" generate_self_signed "default" "admin@localhost"
  
  # Generate startup certificates for all subdomains
  CONFIG_FILE="$(dirname "$0")/../../jstack.config"
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    for subdomain in "api.$DOMAIN" "studio.$DOMAIN" "n8n.$DOMAIN"; do
      log "Generating startup SSL certificate for $subdomain..."
      bash "$(dirname "$0")/ssl_cert.sh" generate_self_signed "$subdomain" "$EMAIL"
    done
  fi
  log "Setting up SSL certificates for service subdomains..."
  bash "$(dirname "$0")/setup_service_subdomains_ssl.sh"
  
  # Deploy services first (without full nginx configs)
  log "Deploying services via Docker Compose..."
  SUPABASE_USER="$SUPABASE_USER" \
  SUPABASE_PASSWORD="$SUPABASE_PASSWORD" \
  SUPABASE_JWT_SECRET="$SUPABASE_JWT_SECRET" \
  SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
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
  
  log "Preparing SSL certificate acquisition..."
  CONFIG_FILE="$(dirname "$0")/../../jstack.config"
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    
    # Create simple nginx config for ACME challenges
    NGINX_CONF_DIR="$(dirname "$0")/../../nginx/conf.d"
    log "Creating simplified nginx config for SSL certificate acquisition..."
    
    # Ensure webroot directory exists with proper permissions
    WEBROOT_DIR="$(dirname "$0")/../../nginx/certbot/www"
    sudo mkdir -p "$WEBROOT_DIR/.well-known/acme-challenge"
    sudo chown -R $(whoami):$(whoami) "$(dirname "$0")/../../nginx/certbot/"
    
    # Backup existing configs
    mkdir -p "$(dirname "$0")/../../nginx/conf.d.backup"
    cp -r "$NGINX_CONF_DIR"/* "$(dirname "$0")/../../nginx/conf.d.backup/" 2>/dev/null || true
    
    # Remove complex configs and create simple ACME-only config
    rm -f "$NGINX_CONF_DIR"/*.conf
    cat > "$NGINX_CONF_DIR/acme-only.conf" <<'EOF'
server {
    listen 80 default_server;
    server_name _;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }
    
    location / {
        return 200 "ACME validation server";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Restart nginx with simple config
    log "Starting nginx with ACME-only configuration..."
    run_docker_command docker-compose -f "$COMPOSE_FILE" restart nginx
    sleep 15
    
    # Get SSL certificates using webroot method with timeout
    log "Attempting SSL certificate issuance for service subdomains..."
    for SUBDOMAIN in "api.$DOMAIN" "n8n.$DOMAIN" "studio.$DOMAIN"; do
      log "Getting SSL certificate for $SUBDOMAIN..."
      
      # Check if certificate already exists
      if docker-compose -f "$COMPOSE_FILE" run --rm --entrypoint="" certbot certbot certificates | grep -q "$SUBDOMAIN"; then
        log "⚠ Certificate for $SUBDOMAIN already exists, attempting renewal..."
        if timeout 120 docker-compose -f "$COMPOSE_FILE" run --rm certbot renew --cert-name "$SUBDOMAIN" --force-renewal --non-interactive; then
          log "✓ SSL certificate renewed for $SUBDOMAIN"
        else
          log "⚠ Failed to renew SSL certificate for $SUBDOMAIN - continuing with existing certificate"
        fi
      else
        log "Requesting new certificate for $SUBDOMAIN..."
        if timeout 120 docker-compose -f "$COMPOSE_FILE" run --rm certbot certonly --webroot -w /var/www/certbot -d "$SUBDOMAIN" --agree-tos --non-interactive --email "$EMAIL"; then
          log "✓ SSL certificate obtained for $SUBDOMAIN"
        else
          log "⚠ Failed to get SSL certificate for $SUBDOMAIN - continuing with self-signed"
        fi
      fi
    done
    
    # Copy certificates to nginx certbot volume and fix permissions
    log "Copying certificates to nginx volume and setting permissions..."
    if [ -d "/etc/letsencrypt/archive" ]; then
      sudo cp -r /etc/letsencrypt/archive "$(dirname "$0")/../../nginx/certbot/conf/" 2>/dev/null || true
    fi
    if [ -d "/etc/letsencrypt/live" ]; then
      # Copy live directory, excluding any existing ones
      for cert_dir in /etc/letsencrypt/live/*/; do
        cert_name=$(basename "$cert_dir")
        if [ "$cert_name" != "*" ] && [ ! -d "$(dirname "$0")/../../nginx/certbot/conf/live/$cert_name" ]; then
          sudo cp -r "$cert_dir" "$(dirname "$0")/../../nginx/certbot/conf/live/"
        fi
      done
    fi
    
    # Fix ownership and permissions for nginx container (user 101)
    sudo chown -R 101:101 "$(dirname "$0")/../../nginx/certbot/conf/live/" "$(dirname "$0")/../../nginx/certbot/conf/archive/" 2>/dev/null || true
    sudo chmod -R 755 "$(dirname "$0")/../../nginx/certbot/conf/live/" "$(dirname "$0")/../../nginx/certbot/conf/archive/" 2>/dev/null || true
    sudo chmod 644 "$(dirname "$0")/../../nginx/certbot/conf/archive/"*/fullchain*.pem "$(dirname "$0")/../../nginx/certbot/conf/archive/"*/cert*.pem "$(dirname "$0")/../../nginx/certbot/conf/archive/"*/chain*.pem 2>/dev/null || true
    sudo chmod 600 "$(dirname "$0")/../../nginx/certbot/conf/archive/"*/privkey*.pem 2>/dev/null || true
    log "✓ Certificates copied and permissions set"
    
    # Restore original nginx configs
    log "Restoring full nginx configurations..."
    rm -f "$NGINX_CONF_DIR/acme-only.conf"
    cp -r "$(dirname "$0")/../../nginx/conf.d.backup"/* "$NGINX_CONF_DIR/" 2>/dev/null || true
    rm -rf "$(dirname "$0")/../../nginx/conf.d.backup"
    
    # Wait for Kong and other upstream services to be ready
    log "Waiting for upstream services to be ready..."
    sleep 30
    for i in {1..6}; do
      if docker-compose exec supabase-kong curl -s http://localhost:8000 >/dev/null 2>&1; then
        log "✓ Kong service is ready"
        break
      fi
      if [ $i -eq 6 ]; then
        log "⚠ Kong service not ready, proceeding anyway"
      else
        log "Waiting for Kong service... (attempt $i/6)"
        sleep 10
      fi
    done
    
    # Restart nginx with full configs
    log "Restarting nginx with full configuration..."
    run_docker_command docker-compose -f "$COMPOSE_FILE" restart nginx
  else
    log "Config file $CONFIG_FILE not found; skipping certbot SSL setup."
  fi
else
  log "docker-compose.yml not found at $COMPOSE_FILE."
fi

log "Full stack installation completed."
