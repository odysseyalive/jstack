#!/bin/bash
# Setup n8n MCP Proxy for Claude.ai Integration
# This script clones and configures the MCP proxy

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_PROXY_DIR="$JSTACK_ROOT/n8n-mcp-proxy"

log "Setting up n8n MCP Proxy for Claude.ai..."

# Check if proxy directory already exists
if [ -d "$MCP_PROXY_DIR" ]; then
  log "MCP proxy directory already exists at: $MCP_PROXY_DIR"
  log "Skipping clone (use git pull to update)"
else
  log "Cloning n8n-mcp-sse proxy..."
  cd "$JSTACK_ROOT"
  if git clone https://github.com/jacob-dietle/n8n-mcp-sse.git n8n-mcp-proxy; then
    log "✓ MCP proxy cloned successfully"
  else
    log "✗ Failed to clone MCP proxy"
    exit 1
  fi
fi

# Check if MCP proxy service is in docker-compose.yml
if grep -q "n8n-mcp-proxy:" "$JSTACK_ROOT/docker-compose.yml"; then
  log "✓ MCP proxy service already configured in docker-compose.yml"
else
  log "Adding MCP proxy service to docker-compose.yml..."
  
  # Backup docker-compose.yml
  cp "$JSTACK_ROOT/docker-compose.yml" "$JSTACK_ROOT/docker-compose.yml.backup"
  
  # Add the service before the final closing bracket
  # This is a simple append - in production, use a proper YAML parser
  cat >> "$JSTACK_ROOT/docker-compose.yml" << 'COMPOSE_EOF'

  n8n-mcp-proxy:
    build:
      context: ./n8n-mcp-proxy
      dockerfile: Dockerfile
    restart: unless-stopped
    ports:
      - "8080:8000"
    environment:
      - N8N_API_URL=http://n8n:5678/api/v1
      - N8N_API_KEY=${N8N_API_KEY}
      - N8N_WEBHOOK_USERNAME=mcp_client
      - N8N_WEBHOOK_PASSWORD=${MCP_AUTH_TOKEN}
      - DEBUG=false
      - PORT=8000
    depends_on:
      - n8n
COMPOSE_EOF
  
  log "✓ MCP proxy service added to docker-compose.yml"
fi

# Check if MCP_AUTH_TOKEN exists in .env
if ! grep -q "^MCP_AUTH_TOKEN=" "$JSTACK_ROOT/.env" 2>/dev/null; then
  log "Generating MCP_AUTH_TOKEN..."
  MCP_TOKEN=$(openssl rand -hex 32)
  echo "MCP_AUTH_TOKEN=$MCP_TOKEN" >> "$JSTACK_ROOT/.env"
  log "✓ MCP_AUTH_TOKEN generated and saved to .env"
else
  log "✓ MCP_AUTH_TOKEN already exists in .env"
fi

# Check if MCP_URL_HASH exists in .env
if ! grep -q "^MCP_URL_HASH=" "$JSTACK_ROOT/.env" 2>/dev/null; then
  log "Generating MCP_URL_HASH for secure endpoint..."
  MCP_HASH=$(openssl rand -hex 16)
  echo "MCP_URL_HASH=$MCP_HASH" >> "$JSTACK_ROOT/.env"
  log "✓ MCP_URL_HASH generated and saved to .env"
else
  log "✓ MCP_URL_HASH already exists in .env"
  MCP_HASH=$(grep "^MCP_URL_HASH=" "$JSTACK_ROOT/.env" | cut -d'=' -f2)
fi

# Setup nginx configuration for mcp subdomain
log "Setting up nginx configuration for mcp subdomain..."

# Load domain from config
if [ -f "$JSTACK_ROOT/jstack.config" ]; then
  source "$JSTACK_ROOT/jstack.config"
else
  log "⚠ jstack.config not found, using default domain"
  DOMAIN="odysseyalive.com"
fi

MCP_NGINX_CONF="$JSTACK_ROOT/nginx/conf.d/mcp.${DOMAIN}.conf"

if [ -f "$MCP_NGINX_CONF" ]; then
  log "✓ MCP nginx config already exists"
else
  log "Creating nginx configuration for mcp.${DOMAIN}..."
  
  cat > "$MCP_NGINX_CONF" << NGINX_EOF
# MCP Proxy for Claude.ai - JStack Configuration

# HTTP server for ACME challenges
server {
    listen 80;
    server_name mcp.${DOMAIN};

    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        alias /var/www/certbot/.well-known/acme-challenge/;
    }

    # Redirect HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name mcp.${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/mcp.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mcp.${DOMAIN}/privkey.pem;

    # Security headers
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

    # MCP SSE endpoint (with secure hash path)
    location /${MCP_HASH}/sse {
        rewrite ^/${MCP_HASH}(/sse.*)\$ \$1 break;
        proxy_pass http://n8n-mcp-proxy:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # SSE-specific headers
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;

        # Extended timeouts for SSE
        proxy_connect_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_read_timeout 86400s;

        # CORS headers for Claude.ai
        add_header Access-Control-Allow-Origin "https://claude.ai" always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept" always;
        add_header Access-Control-Max-Age 3600 always;

        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
    }

    # MCP SSE endpoint (standard path - needed for callbacks)
    location /sse {
        proxy_pass http://n8n-mcp-proxy:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # SSE-specific headers
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;

        # Extended timeouts for SSE
        proxy_connect_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_read_timeout 86400s;

        # CORS headers for Claude.ai
        add_header Access-Control-Allow-Origin "https://claude.ai" always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept" always;
        add_header Access-Control-Max-Age 3600 always;

        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
    }

    # MCP message endpoint (with secure hash path)
    location /${MCP_HASH}/message {
        rewrite ^/${MCP_HASH}(/message.*)\$ \$1 break;
        proxy_pass http://n8n-mcp-proxy:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # CORS headers for Claude.ai
        add_header Access-Control-Allow-Origin "https://claude.ai" always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept" always;
        add_header Access-Control-Max-Age 3600 always;

        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
    }

    # MCP message endpoint (standard path - needed for callbacks)
    location /message {
        proxy_pass http://n8n-mcp-proxy:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # CORS headers for Claude.ai
        add_header Access-Control-Allow-Origin "https://claude.ai" always;
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept" always;
        add_header Access-Control-Max-Age 3600 always;

        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
    }

    # Health check
    location /healthz {
        proxy_pass http://n8n-mcp-proxy:8000;
        access_log off;
    }
}
NGINX_EOF
  
  log "✓ Nginx configuration created for mcp.${DOMAIN}"
fi

# Start the MCP proxy if docker-compose is available
if command -v docker-compose >/dev/null 2>&1; then
  if [ -f "$JSTACK_ROOT/docker-compose.yml" ]; then
    log "Building and starting MCP proxy..."
    cd "$JSTACK_ROOT"
    if docker-compose build n8n-mcp-proxy >/dev/null 2>&1 && docker-compose up -d n8n-mcp-proxy >/dev/null 2>&1; then
      log "✓ MCP proxy started"
    else
      log "⚠ Failed to start MCP proxy - you may need to start it manually"
    fi

    # Reload nginx if it's running
    if docker ps | grep -q nginx; then
      log "Reloading nginx..."
      if docker exec $(docker ps -q -f name=nginx) nginx -s reload >/dev/null 2>&1; then
        log "✓ Nginx reloaded with MCP configuration"
      else
        log "⚠ Failed to reload nginx - reload manually after SSL cert is acquired"
      fi
    fi
  fi
fi

log "✓ n8n MCP Proxy setup completed"
log ""
log "🔒 SECURE MCP URL (save this):"
log "  https://mcp.${DOMAIN}/${MCP_HASH}/sse"
log ""
log "  This URL includes a random hash for security."
log "  Use this URL when connecting Claude.ai."
log ""
log "If running standalone (not during full install), complete these steps:"
log "  1. Ensure DNS record for mcp.${DOMAIN} points to this server"
log "  2. Get SSL certificate: docker-compose run --rm certbot certonly --webroot -w /var/www/certbot --email ${EMAIL:-admin@${DOMAIN}} -d mcp.${DOMAIN} --agree-tos"
log "  3. Reload nginx: docker exec \$(docker ps -q -f name=nginx) nginx -s reload"
log "  4. Test: curl https://mcp.${DOMAIN}/healthz"
