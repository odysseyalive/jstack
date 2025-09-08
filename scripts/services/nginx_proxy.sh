#!/bin/bash
# NGINX Reverse Proxy Service Module for JStack
# Handles NGINX reverse proxy configuration for Supabase, N8N, and SSL termination

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 NGINX CONTAINER SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_nginx_container() {
    log_section "Setting up NGINX Container"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup NGINX container"
        return 0
    fi
    
    start_section_timer "NGINX Setup"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $nginx_dir/{conf,ssl,logs}" "Create NGINX directories"
    
    # Create main NGINX configuration
    cat > /tmp/nginx.conf << EOF
user nginx;
worker_processes ${NGINX_WORKER_PROCESSES};
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections ${NGINX_WORKER_CONNECTIONS};
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                   '\$status \$body_bytes_sent "\$http_referer" '
                   '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    
    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${NGINX_KEEPALIVE_TIMEOUT};
    types_hash_max_size 2048;
    client_max_body_size ${NGINX_CLIENT_MAX_BODY_SIZE};
    
    # Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level ${NGINX_GZIP_COMPRESSION};
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        image/svg+xml;
    
    # Security Headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Rate Limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=${NGINX_RATE_LIMIT_API};
    limit_req_zone \$binary_remote_addr zone=general:10m rate=${NGINX_RATE_LIMIT_GENERAL};
    limit_req_zone \$binary_remote_addr zone=webhooks:10m rate=${NGINX_RATE_LIMIT_WEBHOOKS};
    
    # Upstream servers
    upstream supabase_api {
        server supabase-kong:8000;
    }
    
    upstream supabase_studio {
        server supabase-studio:3000;
    }
    
    upstream n8n_app {
        server n8n:5678;
    }
    
    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    safe_mv "/tmp/nginx.conf" "$nginx_dir/conf/nginx.conf" "Install NGINX config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$nginx_dir/conf/nginx.conf" "Set NGINX config ownership"
    
    # Create Supabase API configuration
    create_supabase_api_config "$nginx_dir"
    
    # Create Supabase Studio configuration
    create_supabase_studio_config "$nginx_dir"
    
    # Create N8N configuration
    create_n8n_config "$nginx_dir"
    
    # Set ownership for all config files
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$nginx_dir/conf/" "Set NGINX configs ownership"
    
    # Create NGINX Docker Compose
    create_nginx_compose "$nginx_dir"
    
    # NGINX will be started by the SSL setup script after certificates are ready
    
    end_section_timer "NGINX Setup"
    log_success "NGINX container setup completed (ready for SSL)"
}

create_supabase_api_config() {
    local nginx_dir="$1"
    
    cat > /tmp/supabase-api.conf << EOF
# Supabase API Configuration
server {
    listen 80;
    server_name ${SUPABASE_SUBDOMAIN}.${DOMAIN};
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${SUPABASE_SUBDOMAIN}.${DOMAIN};
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Rate limiting for API
    limit_req zone=api burst=20 nodelay;
    
    # Proxy configuration
    location / {
        proxy_pass http://supabase_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
        proxy_buffering off;
    }
}
EOF
    
    safe_mv "/tmp/supabase-api.conf" "$nginx_dir/conf/supabase-api.conf" "Install Supabase API config"
}

create_supabase_studio_config() {
    local nginx_dir="$1"
    
    cat > /tmp/supabase-studio.conf << EOF
# Supabase Studio Configuration
server {
    listen 80;
    server_name ${STUDIO_SUBDOMAIN}.${DOMAIN};
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${STUDIO_SUBDOMAIN}.${DOMAIN};
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Rate limiting for general access
    limit_req zone=general burst=10 nodelay;
    
    # Proxy configuration
    location / {
        proxy_pass http://supabase_studio;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
    }
}
EOF
    
    safe_mv "/tmp/supabase-studio.conf" "$nginx_dir/conf/supabase-studio.conf" "Install Supabase Studio config"
}

create_n8n_config() {
    local nginx_dir="$1"
    
    cat > /tmp/n8n.conf << EOF
# N8N Configuration
server {
    listen 80;
    server_name ${N8N_SUBDOMAIN}.${DOMAIN};
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${N8N_SUBDOMAIN}.${DOMAIN};
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Rate limiting
    limit_req zone=general burst=10 nodelay;
    
    # Special rate limiting for webhooks
    location /webhook {
        limit_req zone=webhooks burst=50 nodelay;
        proxy_pass http://n8n_app;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
    }
    
    # Main N8N interface
    location / {
        proxy_pass http://n8n_app;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_redirect off;
        
        # Increase timeouts for long-running workflows
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 300s;
    }
}
EOF
    
    safe_mv "/tmp/n8n.conf" "$nginx_dir/conf/n8n.conf" "Install N8N config"
}

create_nginx_compose() {
    local nginx_dir="$1"
    
    cat > /tmp/docker-compose.yml << EOF
version: '3.8'

services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./conf/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf/supabase-api.conf:/etc/nginx/conf.d/supabase-api.conf:ro
      - ./conf/supabase-studio.conf:/etc/nginx/conf.d/supabase-studio.conf:ro
      - ./conf/n8n.conf:/etc/nginx/conf.d/n8n.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./logs:/var/log/nginx
      - certbot_conf:/etc/letsencrypt:ro
      - certbot_www:/var/www/certbot:ro
    networks:
      - ${PUBLIC_TIER}
      - ${PRIVATE_TIER}
    deploy:
      resources:
        limits:
          memory: ${NGINX_MEMORY_LIMIT}
          cpus: '${NGINX_CPU_LIMIT}'
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    depends_on:
      - certbot

  certbot:
    image: certbot/certbot:v2.7.4
    container_name: certbot
    volumes:
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
      - ./logs:/var/log/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew --quiet; sleep 12h & wait; done;'"

networks:
  ${PUBLIC_TIER}:
    external: true
  ${PRIVATE_TIER}:
    external: true

volumes:
  certbot_conf:
    driver: local
  certbot_www:
    driver: local
EOF
    
    safe_mv "/tmp/docker-compose.yml" "$nginx_dir/docker-compose.yml" "Install NGINX compose"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$nginx_dir/docker-compose.yml" "Set NGINX compose ownership"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 NGINX SERVICE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

start_nginx_service() {
    log_section "Starting NGINX Service"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would start NGINX service"
        return 0
    fi
    
    local nginx_dir="$BASE_DIR/services/nginx"
    
    if [[ ! -f "$nginx_dir/docker-compose.yml" ]]; then
        log_error "NGINX not configured. Run setup first."
        return 1
    fi
    
    start_section_timer "NGINX Service Start"
    
    # Start NGINX and certbot containers
    docker_cmd "cd $nginx_dir && docker-compose up -d" "Start NGINX containers"
    
    # Wait for NGINX to be healthy
    wait_for_service_health "nginx-proxy" 60 5
    
    end_section_timer "NGINX Service Start"
    log_success "NGINX service started successfully"
}

stop_nginx_service() {
    log_section "Stopping NGINX Service"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would stop NGINX service"
        return 0
    fi
    
    local nginx_dir="$BASE_DIR/services/nginx"
    
    if [[ ! -f "$nginx_dir/docker-compose.yml" ]]; then
        log_warning "NGINX not configured"
        return 0
    fi
    
    # Stop NGINX containers
    docker_cmd "cd $nginx_dir && docker-compose down" "Stop NGINX containers"
    
    log_success "NGINX service stopped successfully"
}

reload_nginx_config() {
    log_section "Reloading NGINX Configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would reload NGINX config"
        return 0
    fi
    
    # Test configuration first
    if docker_cmd "docker exec nginx-proxy nginx -t" "Test NGINX configuration"; then
        log_success "NGINX configuration test passed"
        
        # Reload configuration
        docker_cmd "docker exec nginx-proxy nginx -s reload" "Reload NGINX configuration"
        log_success "NGINX configuration reloaded successfully"
    else
        log_error "NGINX configuration test failed - not reloading"
        return 1
    fi
}

check_nginx_status() {
    log_section "NGINX Service Status"
    
    # Check if container is running
    if docker ps --filter name=nginx-proxy --filter status=running --quiet | grep -q .; then
        log_success "NGINX container is running"
        
        # Show detailed status
        docker ps --filter name=nginx-proxy --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"
        
        # Show upstream status
        echo ""
        log_info "Testing upstream services:"
        
        # Test Supabase API
        if curl -s -o /dev/null -w "%{http_code}" "https://${SUPABASE_SUBDOMAIN}.${DOMAIN}/health" | grep -q "200"; then
            log_success "Supabase API upstream is healthy"
        else
            log_warning "Supabase API upstream may have issues"
        fi
        
        # Test Supabase Studio
        if curl -s -o /dev/null -w "%{http_code}" "https://${STUDIO_SUBDOMAIN}.${DOMAIN}/api/health" | grep -q "200"; then
            log_success "Supabase Studio upstream is healthy"
        else
            log_warning "Supabase Studio upstream may have issues"
        fi
        
        # Test N8N
        if curl -s -o /dev/null -w "%{http_code}" "https://${N8N_SUBDOMAIN}.${DOMAIN}/healthz" | grep -q "200"; then
            log_success "N8N upstream is healthy"
        else
            log_warning "N8N upstream may have issues"
        fi
        
    else
        log_error "NGINX container is not running"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN SERVICE ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-setup}" in
        "setup"|"deploy")
            setup_nginx_container
            ;;
        "start")
            start_nginx_service
            ;;
        "stop")
            stop_nginx_service
            ;;
        "restart")
            stop_nginx_service
            sleep 2
            start_nginx_service
            ;;
        "reload")
            reload_nginx_config
            ;;
        "status")
            check_nginx_status
            ;;
        "logs")
            service_name="${2:-nginx-proxy}"
            log_info "Showing logs for: $service_name"
            docker logs "$service_name"
            ;;
        "test")
            log_info "Testing NGINX configuration"
            docker exec nginx-proxy nginx -t
            ;;
        *)
            echo "Usage: $0 [setup|start|stop|restart|reload|status|logs|test]"
            echo ""
            echo "Commands:"
            echo "  setup   - Setup NGINX container and configuration"
            echo "  start   - Start NGINX service"
            echo "  stop    - Stop NGINX service" 
            echo "  restart - Restart NGINX service"
            echo "  reload  - Reload NGINX configuration"
            echo "  status  - Check NGINX and upstream status"
            echo "  logs    - Show NGINX logs"
            echo "  test    - Test NGINX configuration syntax"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi