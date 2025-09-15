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

log "Enabling HTTPS redirects for all configured domains..."

# Replace landing page blocks with HTTPS redirects in all config files
CONFIG_FILES=(
    "default.conf"
    "api.${DOMAIN}.conf"
    "studio.${DOMAIN}.conf"
    "n8n.${DOMAIN}.conf"
)

for config_file in "${CONFIG_FILES[@]}"; do
    config_path="$NGINX_CONF_DIR/$config_file"
    
    if [ -f "$config_path" ]; then
        log "Updating $config_file..."
        
        # Use sed to replace landing page block with HTTPS redirect
        sed -i '/# Serve landing page during setup/,/index index.html;/ {
            s|# Serve landing page during setup|# Redirect all other traffic to HTTPS|
            s|root /usr/share/nginx/html/default;||
            s|index index.html;|return 301 https://\$host\$request_uri;|
        }' "$config_path"
        
        log "✓ Updated $config_file"
    else
        log "⚠ Config file not found: $config_path"
    fi
done

# Restart nginx to apply changes
log "Restarting nginx to apply HTTPS redirect configuration..."
if docker-compose restart nginx >/dev/null 2>&1; then
    log "✓ Nginx restarted successfully"
else
    log "⚠ Failed to restart nginx"
    exit 1
fi

log "✓ HTTPS redirects enabled for all domains"