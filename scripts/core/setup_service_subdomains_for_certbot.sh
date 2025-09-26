#!/bin/bash
# JStack Service Subdomains (No SSL) Setup Script - Initial Installation
# Usage: setup_service_subdomains_for_certbot.sh

set -e

# Load configuration
CONFIG_FILE="$(dirname "$0")/../../jstack.config"
if [ -f "${CONFIG_FILE}" ]; then
  source "${CONFIG_FILE}"
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

# Generate site-specific nginx config for --install-site
generate_site_nginx_config() {
  local site_domain="${1:-$DOMAIN}"
  local site_port="${2:-80}"
  local site_container="${3:-}"

  if [[ -z "${site_domain}" || -z "${site_port}" ]]; then
    log "ERROR: generate_site_nginx_config requires domain and port"
    return 1
  fi

  # Default to external proxy if no container name provided
  local proxy_target="http://172.17.0.1:${site_port}"
  if [[ -n "${site_container}" ]]; then
    proxy_target="http://${site_container}:${site_port}"
  fi

  log "Generating nginx config for site: ${site_domain}"

  local nginx_conf_dir="nginx/conf.d"
  mkdir -p "${nginx_conf_dir}"

  cat >"${nginx_conf_dir}/${site_domain}.conf" <<"EOF"
# Site Configuration for ${site_domain} - JStack (No SSL)

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

  log "✓ Generated nginx config for ${site_domain}"
}

# Install SSL certificate for additional site domain
install_site_ssl_certificate() {
  local site_domain="${1:-$DOMAIN}"

  if [[ -z "${site_domain}" ]]; then
    log "ERROR: install_site_ssl_certificate requires domain"
    return 1
  fi

  log "Installing SSL certificate for site: ${site_domain}"

  # Add the site domain to our certificate (Let's Encrypt supports multiple SANs)
  local all_domains="${DOMAIN} api.${DOMAIN} studio.${DOMAIN} n8n.${DOMAIN} chrome.${DOMAIN} ${site_domain}"
  local certbot_dir="./nginx/certbot"

  # Build domain arguments
  local domain_args=""
  for domain in $all_domains; do
    domain_args="${domain_args} -d ${domain}"
  done

  # Select email argument
  local email_arg="--email ${EMAIL}"
  if [[ -z "${EMAIL}" || "${EMAIL}" == "admin@example.com" ]]; then
    email_arg="--register-unsafely-without-email"
    log "⚠ No email configured, using unsafe registration"
  fi

  # Request updated certificate with new domain
  if docker-compose run --rm --entrypoint="" certbot certbot certonly --webroot -w /var/www/certbot ${email_arg} ${domain_args} --rsa-key-size 2048 --agree-tos --force-renewal --expand --non-interactive >/dev/null 2>&1; then
    log "✓ SSL certificate updated to include ${site_domain}"

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
    log "⚠ Failed to update SSL certificate for ${site_domain}"
    log "⚠ You may need to:"
    log "  - Ensure ${site_domain} points to this server"
    log "  - Check Let's Encrypt rate limits"
    log "⚠ The site will work with a certificate warning"
    return 1
  fi
}

# Generate NGINX configuration files dynamically
generate_nginx_configs() {
  log "Generating NGINX configuration files for domain: ${DOMAIN}"

  local nginx_conf_dir="nginx/conf.d"
  mkdir -p "${nginx_conf_dir}"

  # Generate default.conf
  log "Creating default.conf..."
  cat >"${nginx_conf_dir}/default.conf" <<"EOF"
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
  cat >"${nginx_conf_dir}/api.${DOMAIN}.conf" <<"EOF"
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

  # Generate Studio config (Supabase Studio)
  log "Creating studio.${DOMAIN}.conf..."
  cat >"${nginx_conf_dir}/studio.${DOMAIN}.conf" <<"EOF"
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
  cat >"${nginx_conf_dir}/n8n.${DOMAIN}.conf" <<"EOF"
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

  log "✓ All NGINX configuration files generated successfully"
}

# Update NGINX config files with actual domain
log "Updating NGINX configs with domain: ${DOMAIN}"

# Remove any existing example.com config files
rm -f nginx/conf.d/*.example.com.conf 2>/dev/null || true

# Generate all nginx configs dynamically
generate_nginx_configs

log "✓ Service subdomain SSL setup complete"

