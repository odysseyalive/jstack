#!/bin/bash
# JStack Service Subdomains SSL Setup Script - Fixed Version
# Usage: setup_service_subdomains_ssl.sh

set -e

# Load configuration
CONFIG_FILE="$(dirname "$0")/../../jstack.config"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  # Fallback to default config
  source "$(dirname "$0")/../../jstack.config.default" 2>/dev/null || true
fi

# Extract domain from config
DOMAIN="${DOMAIN:-example.com}"
EMAIL="${EMAIL:-admin@example.com}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Bootstrap SSL certificates using nginx-certbot webroot approach
bootstrap_ssl_certificates() {
  log "Bootstrapping SSL certificates for $DOMAIN and subdomains..."

  local all_domains="${DOMAIN} api.${DOMAIN} studio.${DOMAIN} n8n.${DOMAIN} chrome.${DOMAIN}"
  local certbot_dir="./nginx/certbot"

  # Step 1: Create directories
  log "Creating SSL certificate directories..."
  mkdir -p "$certbot_dir/conf" "$certbot_dir/www"

  # Step 2: Download recommended TLS parameters if needed
  log "Ensuring TLS parameters are available..."
  if [[ ! -f "$certbot_dir/conf/options-ssl-nginx.conf" ]]; then
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf >"$certbot_dir/conf/options-ssl-nginx.conf"
    log "✓ Downloaded SSL nginx config"
  fi

  if [[ ! -f "$certbot_dir/conf/ssl-dhparams.pem" ]]; then
    curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem >"$certbot_dir/conf/ssl-dhparams.pem"
    log "✓ Downloaded SSL DH params"
  fi

  # Step 3: Start nginx with existing configs
  log "Starting nginx with existing configs..."
  if docker-compose up --force-recreate -d nginx >/dev/null 2>&1; then
    log "✓ Nginx started with existing configs"
    sleep 10 # Give nginx time to fully start
  else
    log "⚠ Failed to start nginx, trying restart..."
    docker-compose restart nginx >/dev/null 2>&1 || true
    sleep 10
  fi

  # Step 4: Check if domains resolve
  log "Checking domain resolution..."
  local domains_resolved=0
  for domain in $all_domains; do
    if command -v dig >/dev/null 2>&1; then
      if dig +short "$domain" A | grep -q .; then
        log "✓ $domain resolves"
        domains_resolved=$((domains_resolved + 1))
      else
        log "⚠ $domain does not resolve"
      fi
    else
      log "⚠ dig not available, skipping DNS check"
      domains_resolved=5 # Assume all resolve if we can't check
      break
    fi
  done

  if [ $domains_resolved -eq 0 ]; then
    log "⚠ No domains resolve - SSL setup will fail"
    log "⚠ Please configure DNS for: $all_domains"
    return 1
  fi

  # Step 4: Request real certificates using webroot
  log "Requesting real Let's Encrypt certificates..."

  # Build domain arguments
  local domain_args=""
  for domain in $all_domains; do
    domain_args="$domain_args -d $domain"
  done

  # Select email argument
  local email_arg="--email $EMAIL"
  if [[ -z "$EMAIL" || "$EMAIL" == "admin@example.com" ]]; then
    email_arg="--register-unsafely-without-email"
    log "⚠ No email configured, using unsafe registration"
  fi

  # Check if certificates already exist
  local cert_exists=false
  if docker-compose run --rm --entrypoint="" certbot ls | grep -q "$DOMAIN"; then
    log "⚠ Certificates already exist for $DOMAIN, attempting renewal..."
    cert_exists=true
  fi

  # Request certificates using webroot mode with timeout
  local cert_command=""
  if [ "$cert_exists" = true ]; then
    cert_command="certbot renew --cert-name $DOMAIN --force-renewal --non-interactive"
  else
    cert_command="certbot certonly --webroot -w /var/www/certbot $email_arg $domain_args --rsa-key-size 2048 --agree-tos --non-interactive"
  fi

  log "Running: $cert_command"
  if timeout 180 docker-compose run --rm --entrypoint="" certbot $cert_command; then
    log "✓ Real SSL certificates acquired successfully"

    # Step 5: Reload nginx with real certificates
    log "Reloading nginx with real certificates..."
    if docker-compose exec nginx nginx -s reload >/dev/null 2>&1; then
      log "✓ Nginx reloaded with real certificates"
    else
      log "⚠ Failed to reload nginx, restarting container..."
      docker-compose restart nginx >/dev/null 2>&1
      log "✓ Nginx restarted with real certificates"
    fi

    return 0
  else
    log "⚠ Failed to acquire real SSL certificates"
    log "⚠ This could be due to:"
    log "  - Domain DNS not pointing to this server"
    log "  - Rate limiting from Let's Encrypt"
    log "  - Firewall blocking port 80"
    log "⚠ Nginx will continue running with self-signed certificates"

    # Generate self-signed certificates as fallback
    log "Generating self-signed certificates as fallback..."
    mkdir -p "$certbot_dir/conf/live/$DOMAIN"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$certbot_dir/conf/live/$DOMAIN/privkey.pem" \
      -out "$certbot_dir/conf/live/$DOMAIN/fullchain.pem" \
      -subj "/C=${SSL_COUNTRY:-US}/ST=${SSL_STATE:-State}/L=${SSL_CITY:-City}/O=${SSL_ORGANIZATION:-Organization}/OU=${SSL_ORG_UNIT:-IT}/CN=$DOMAIN" \
      >/dev/null 2>&1

    log "✓ Self-signed certificate generated as fallback"

    # Reload nginx with self-signed certs
    docker-compose exec nginx nginx -s reload >/dev/null 2>&1 || docker-compose restart nginx >/dev/null 2>&1
    log "✓ Nginx reloaded with self-signed certificates"

    return 1
  fi
}

# Main execution
log "Setting up SSL certificates for service subdomains..."

# Bootstrap SSL certificates - DISABLED, handled by main installation script
#if bootstrap_ssl_certificates; then
#    log "✓ SSL certificate setup completed successfully"
#else
#    log "⚠ SSL certificate setup completed with fallback certificates"
#fi
log "Skipping SSL bootstrap - will be handled by main installation process"

# Set proper permissions
find nginx/certbot/conf -name "*.pem" -exec chmod 600 {} \; 2>/dev/null || true
find nginx/certbot/conf -type d -exec chmod 700 {} \; 2>/dev/null || true

# Generate site-specific nginx config for --install-site
generate_site_nginx_config() {
  local site_domain="$1"
  local site_port="$2"
  local site_container="$3"

  if [[ -z "$site_domain" || -z "$site_port" ]]; then
    log "ERROR: generate_site_nginx_config requires domain and port"
    return 1
  fi

  # Default to external proxy if no container name provided
  local proxy_target="http://172.17.0.1:${site_port}"
  if [[ -n "$site_container" ]]; then
    proxy_target="http://${site_container}:${site_port}"
  fi

  log "Generating nginx config for site: $site_domain"

  local nginx_conf_dir="nginx/conf.d"
  mkdir -p "$nginx_conf_dir"

  cat >"$nginx_conf_dir/${site_domain}.conf" <<EOF
# Site Configuration for ${site_domain} - JStack

# HTTP server for ACME challenges
server {
    listen 80;
    server_name ${site_domain};
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Serve landing page during setup
    location / {
        root /usr/share/nginx/html/default;
        index index.html;
    }
}


EOF

# Install SSL certificate for additional site domain
install_site_ssl_certificate() {
  local site_domain="$1"

  if [[ -z "$site_domain" ]]; then
    log "ERROR: install_site_ssl_certificate requires domain"
    return 1
  fi

  log "Installing SSL certificate for site: $site_domain"

  # Add the site domain to our certificate (Let's Encrypt supports multiple SANs)
  local all_domains="${DOMAIN} api.${DOMAIN} studio.${DOMAIN} n8n.${DOMAIN} chrome.${DOMAIN} ${site_domain}"
  local certbot_dir="./nginx/certbot"

  # Build domain arguments
  local domain_args=""
  for domain in $all_domains; do
    domain_args="$domain_args -d $domain"
  done

  # Select email argument
  local email_arg="--email $EMAIL"
  if [[ -z "$EMAIL" || "$EMAIL" == "admin@example.com" ]]; then
    email_arg="--register-unsafely-without-email"
    log "⚠ No email configured, using unsafe registration"
  fi

  # Request updated certificate with new domain
  if docker-compose run --rm --entrypoint="" certbot certbot certonly --webroot -w /var/www/certbot $email_arg $domain_args --rsa-key-size 2048 --agree-tos --force-renewal --expand --non-interactive >/dev/null 2>&1; then
    log "✓ SSL certificate updated to include $site_domain"

    # Reload nginx
    if docker-compose exec nginx nginx -s reload >/dev/null 2>&1; then
      log "✓ Nginx reloaded with updated certificate"
    else
      log "⚠ Failed to reload nginx, restarting container..."
      docker-compose restart nginx >/dev/null 2>&1
      log "✓ Nginx restarted"
    fi

    return 0
  else
    log "⚠ Failed to update SSL certificate for $site_domain"
    log "⚠ You may need to:"
    log "  - Ensure $site_domain points to this server"
    log "  - Check Let's Encrypt rate limits"
    log "⚠ The site will work with a certificate warning"
    return 1
  fi
}

generate_nginx_configs() {
  log "Generating NGINX configuration files for domain: $DOMAIN"

  local nginx_conf_dir="nginx/conf.d"
  mkdir -p "$nginx_conf_dir"

  # Generate default.conf
  log "Creating default.conf..."
  cat >"$nginx_conf_dir/default.conf" <<EOF
# Default site config for JStack NGINX (workspace-managed)
server {
    listen 80;
    server_name _;
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Serve landing page during setup
    location / {
        root /usr/share/nginx/html/default;
        index index.html;
    }
}

EOF

  # Generate API config (Supabase Kong)
  log "Creating api.${DOMAIN}.conf..."
  cat >"$nginx_conf_dir/api.${DOMAIN}.conf" <<EOF
# Supabase API Gateway (Kong) - JStack Configuration

# HTTP server for ACME challenges
server {
    listen 80;
    server_name api.${DOMAIN};
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Serve landing page during setup
    location / {
        root /usr/share/nginx/html/default;
        index index.html;
    }
}




EOF

# Update NGINX config files with actual domain
  # Generate Studio config (Supabase Studio)
  log "Creating studio.${DOMAIN}.conf..."
  cat >"$nginx_conf_dir/studio.${DOMAIN}.conf" <<EOF
# Supabase Studio Dashboard - JStack Configuration

# HTTP server for ACME challenges
server {
    listen 80;
    server_name studio.${DOMAIN};
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
 
    # Serve landing page during setup
    location / {
        root /usr/share/nginx/html/default;
        index index.html;
    }   
}
EOF

  # Generate N8N config
  log "Creating n8n.${DOMAIN}.conf..."
  cat >"$nginx_conf_dir/n8n.${DOMAIN}.conf" <<EOF
# n8n Workflow Automation - JStack Configuration

# HTTP server for ACME challenges
server {
    listen 80;
    server_name n8n.${DOMAIN};
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
   
    # Serve landing page during setup
    location / {
        root /usr/share/nginx/html/default;
        index index.html;
    }
}
EOF

  # Generate Chrome config
  log "Creating chrome.${DOMAIN}.conf..."
  cat >"$nginx_conf_dir/chrome.${DOMAIN}.conf" <<EOF
# Browserless Chrome - JStack Configuration

# HTTP server for ACME challenges
server {
    listen 80;
    server_name chrome.${DOMAIN};
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Serve landing page during setup
    location / {
        root /usr/share/nginx/html/default;
        index index.html;
    }
}
EOF

  log "✓ All NGINX configuration files generated successfully"
}

log "Updating NGINX configs with domain: $DOMAIN"

# Remove any existing example.com config files
rm -f nginx/conf.d/*.example.com.conf 2>/dev/null || true

# Generate all nginx configs dynamically
generate_nginx_configs

log "✓ Service subdomain SSL setup complete"

