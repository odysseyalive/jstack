#!/bin/bash
# Enable HTTPS Redirects Script
# Usage: enable_https_redirects.sh
# Replaces landing page serving with HTTPS redirects after SSL certificates are acquired

set -e

# Load configuration
CONFIG_FILE="$(dirname "$0")/../../jstack.config"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  # Fallback to default config
  source "$(dirname "$0")/../../jstack.config.default" 2>/dev/null || true
fi

DOMAIN="${DOMAIN:-example.com}"
NGINX_CONF_DIR="$(dirname "$0")/../../nginx/conf.d"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Certificate validation function
add_cert_check() {
  local domain="$1"
  if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${domain}/privkey.pem" ]; then
    return 0
  else
    return 1
  fi
}

# HTTPS block functions
add_default_https_block() {
  cat >>"$1" <<EOF
server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/letsencrypt/live/api.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.${DOMAIN}/privkey.pem;
    location / {
        root   /usr/share/nginx/default/html;
        index  index.html index.htm;
    }
}
EOF
}

add_api_https_block() {
  cat >>"$1" <<EOF
server {
    listen 443 ssl;
    server_name api.${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/api.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.${DOMAIN}/privkey.pem;
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    # Proxy to Supabase Kong API Gateway
    location / {
        proxy_pass http://supabase-kong:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support for realtime
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
}

add_studio_https_block() {
  cat >>"$1" <<EOF
server {
    listen 443 ssl;
    server_name studio.${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/studio.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/studio.${DOMAIN}/privkey.pem;
    # Security headers
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    # Proxy to Supabase Studio
    location / {
        # HTTP Basic Authentication
        auth_basic "Supabase Studio - Restricted Access";
        auth_basic_user_file /etc/nginx/htpasswd;
        
        proxy_pass http://supabase-studio:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
}

add_n8n_https_block() {
  cat >>"$1" <<EOF
server {
    listen 443 ssl;
    server_name n8n.${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/n8n.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/n8n.${DOMAIN}/privkey.pem;
    # Security headers
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    # Proxy to n8n
    location / {
        proxy_pass http://n8n:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support for n8n
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
}

add_chrome_https_block() {
  cat >>"$1" <<EOF
server {
    listen 443 ssl;
    server_name chrome.${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/chrome.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/chrome.${DOMAIN}/privkey.pem;
    # Security headers
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
    # Proxy to Browserless Chrome
    location / {
        proxy_pass http://chrome:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support for Chrome DevTools
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
}

log "Enabling HTTPS redirects for all configured domains..."

# Define subdomains to process
SUBDOMAINS=("api" "studio" "n8n" "chrome")

# Process each subdomain for HTTPS enablement

for subdomain in "${SUBDOMAINS[@]}"; do
  domain="${subdomain}.${DOMAIN}"
  config_file="${subdomain}.${DOMAIN}.conf"
  config_path="$NGINX_CONF_DIR/$config_file"

  if [ -f "$config_path" ]; then
    log "Processing $config_file..."

    # Check if certificate exists (Let's Encrypt or self-signed)
    if add_cert_check "$domain"; then
      log "✓ Certificate found for $domain - enabling HTTPS"

      # Add HTTPS server block based on subdomain type
      case "$subdomain" in
      "api")
        add_api_https_block "$config_path"
        ;;
      "studio")
        add_studio_https_block "$config_path"
        ;;
      "n8n")
        add_n8n_https_block "$config_path"
        ;;
      "chrome")
        # Chrome uses default-like config, add basic HTTPS block
        add_chrome_https_block "$config_path"
        ;;
      esac

      # Replace HTTP landing page with HTTPS redirect
      sed -i '/# Serve landing page during setup/,/index index.html;/ {
                s|# Serve landing page during setup|# Redirect HTTP to HTTPS|
                s|root /usr/share/nginx/default/html;||
                s|index index.html;|return 301 https://$host$request_uri;|
            }' "$config_path"

      log "✓ HTTPS enabled for $domain"
    else
      log "⚠ No certificate found for $domain - keeping HTTP-only access"
      log "  Manual certificate setup required for HTTPS"
    fi
  else
    log "⚠ Config file not found: $config_path"
  fi
done

# Restart nginx to apply changes
log "Restarting nginx to apply HTTPS configuration..."
if docker-compose restart nginx >/dev/null 2>&1; then
  log "✓ Nginx restarted successfully"
else
  log "⚠ Failed to restart nginx"
  exit 1
fi

log "✓ HTTPS blocks added for domains with valid certificates"

