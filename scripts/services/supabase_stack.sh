#!/bin/bash
# Supabase Stack Service Module for JStack
# Handles PostgreSQL, Supabase API, Studio, Kong, Auth, REST, Realtime, Storage, and Meta services

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🗄️ SUPABASE CONTAINERS SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_supabase_containers() {
    log_section "Setting up Supabase Containers"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Supabase containers"
        return 0
    fi
    
    start_section_timer "Supabase Setup"
    
    local supabase_dir="$BASE_DIR/services/supabase"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $supabase_dir" "Create Supabase directory"
    
    # Generate Supabase secrets
    log_info "Generating Supabase secrets"
    local postgres_password=$(generate_password)
    local jwt_secret=$(generate_secret)
    local anon_key=$(generate_secret)
    local service_role_key=$(generate_secret)
    local site_url="https://${DOMAIN}"
    local api_external_url="https://${SUPABASE_SUBDOMAIN}.${DOMAIN}"
    local studio_external_url="https://${STUDIO_SUBDOMAIN}.${DOMAIN}"
    
    # Create Supabase environment file
    cat > /tmp/supabase.env << EOF
# Supabase Configuration for JStack
POSTGRES_PASSWORD=$postgres_password
POSTGRES_DB=$SUPABASE_DB_NAME
POSTGRES_USER=postgres

# JWT Configuration
JWT_SECRET=$jwt_secret
ANON_KEY=$anon_key
SERVICE_ROLE_KEY=$service_role_key

# API Configuration
API_EXTERNAL_URL=$api_external_url
SITE_URL=$site_url
ADDITIONAL_REDIRECT_URLS=
DISABLE_SIGNUP=false
ENABLE_EMAIL_CONFIRMATIONS=false
ENABLE_EMAIL_AUTOCONFIRM=true
ENABLE_PHONE_CONFIRMATIONS=false
ENABLE_PHONE_AUTOCONFIRM=true

# Studio Configuration
STUDIO_EXTERNAL_URL=$studio_external_url
SUPABASE_AUTH_EXTERNAL_APPLE_ENABLED=false
SUPABASE_AUTH_EXTERNAL_AZURE_ENABLED=false
SUPABASE_AUTH_EXTERNAL_BITBUCKET_ENABLED=false
SUPABASE_AUTH_EXTERNAL_DISCORD_ENABLED=false
SUPABASE_AUTH_EXTERNAL_FACEBOOK_ENABLED=false
SUPABASE_AUTH_EXTERNAL_GITHUB_ENABLED=false
SUPABASE_AUTH_EXTERNAL_GITLAB_ENABLED=false
SUPABASE_AUTH_EXTERNAL_GOOGLE_ENABLED=false
SUPABASE_AUTH_EXTERNAL_KEYCLOAK_ENABLED=false
SUPABASE_AUTH_EXTERNAL_LINKEDIN_ENABLED=false
SUPABASE_AUTH_EXTERNAL_NOTION_ENABLED=false
SUPABASE_AUTH_EXTERNAL_TWITCH_ENABLED=false
SUPABASE_AUTH_EXTERNAL_TWITTER_ENABLED=false
SUPABASE_AUTH_EXTERNAL_SLACK_ENABLED=false
SUPABASE_AUTH_EXTERNAL_SPOTIFY_ENABLED=false
SUPABASE_AUTH_EXTERNAL_WORKOS_ENABLED=false
SUPABASE_AUTH_EXTERNAL_ZOOM_ENABLED=false

# Database Configuration
POSTGRES_HOST=supabase-db
POSTGRES_PORT=5432

# Security
GOTRUE_JWT_EXP=3600
GOTRUE_RATE_LIMIT_EMAIL_SENT=100
GOTRUE_RATE_LIMIT_SMS_SENT=100
GOTRUE_RATE_LIMIT_TOKEN_REFRESH=50
GOTRUE_RATE_LIMIT_VERIFY=300

# Realtime
REALTIME_DB_ENC_KEY=$(generate_secret | cut -c1-32)

# Storage
STORAGE_BACKEND=file
STORAGE_FILE_SIZE_LIMIT=52428800
STORAGE_S3_ENABLED=false

# Analytics
LOGFLARE_API_KEY=
LOGFLARE_SOURCE_TOKEN=

# Webhook
WEBHOOK_SECRET=
EOF
    
    safe_mv "/tmp/supabase.env" "$supabase_dir/.env" "Install Supabase environment"
    safe_chmod "600" "$supabase_dir/.env" "Secure Supabase environment"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$supabase_dir/.env" "Set Supabase env ownership"
    
    # Create Supabase Docker Compose
    cat > /tmp/docker-compose.yml << EOF
version: '3.8'

services:
  # PostgreSQL Database
  supabase-db:
    image: postgres:15-alpine
    container_name: supabase-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
    volumes:
      - supabase_db_data:/var/lib/postgresql/data
      - ./config/init:/docker-entrypoint-initdb.d:ro
    networks:
      - ${PRIVATE_TIER}
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
    deploy:
      resources:
        limits:
          memory: ${POSTGRES_MEMORY_LIMIT}
          cpus: '${POSTGRES_CPU_LIMIT}'
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  # Supabase Kong API Gateway
  supabase-kong:
    image: kong:3.4-alpine
    container_name: supabase-kong
    restart: unless-stopped
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
      KONG_DNS_ORDER: LAST,A,CNAME
      KONG_PLUGINS: request-transformer,cors,key-auth,acl,basic-auth
      KONG_NGINX_PROXY_PROXY_BUFFER_SIZE: 160k
      KONG_NGINX_PROXY_PROXY_BUFFERS: 64 160k
    volumes:
      - ./config/kong.yml:/var/lib/kong/kong.yml:ro
    ports:
      - "${SUPABASE_API_PORT}:8000"
    networks:
      - ${PUBLIC_TIER}
      - ${PRIVATE_TIER}
    depends_on:
      supabase-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9999/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase Auth
  supabase-auth:
    image: supabase/gotrue:v2.143.0
    container_name: supabase-auth
    restart: unless-stopped
    environment:
      GOTRUE_API_HOST: 0.0.0.0
      GOTRUE_API_PORT: 9999
      API_EXTERNAL_URL: \${API_EXTERNAL_URL}
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@supabase-db:5432/\${POSTGRES_DB}?search_path=auth&sslmode=disable
      GOTRUE_SITE_URL: \${SITE_URL}
      GOTRUE_URI_ALLOW_LIST: \${ADDITIONAL_REDIRECT_URLS}
      GOTRUE_DISABLE_SIGNUP: \${DISABLE_SIGNUP}
      GOTRUE_JWT_SECRET: \${JWT_SECRET}
      GOTRUE_JWT_EXP: \${GOTRUE_JWT_EXP}
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_JWT_ADMIN_ROLES: service_role
      GOTRUE_JWT_AUD: authenticated
      GOTRUE_JWT_DEFAULT_GROUP_NAME: authenticated
      GOTRUE_EXTERNAL_EMAIL_ENABLED: true
      GOTRUE_MAILER_AUTOCONFIRM: \${ENABLE_EMAIL_AUTOCONFIRM}
      GOTRUE_SMTP_ADMIN_EMAIL: \${EMAIL}
      GOTRUE_SMTP_HOST: 
      GOTRUE_SMTP_PORT: 587
      GOTRUE_SMTP_USER: 
      GOTRUE_SMTP_PASS: 
      GOTRUE_MAILER_URLPATHS_INVITE: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_CONFIRMATION: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_RECOVERY: /auth/v1/verify
      GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: /auth/v1/verify
    networks:
      - ${PRIVATE_TIER}
    depends_on:
      supabase-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9999/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase REST API
  supabase-rest:
    image: postgrest/postgrest:v12.0.2
    container_name: supabase-rest
    restart: unless-stopped
    environment:
      PGRST_DB_URI: postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@supabase-db:5432/\${POSTGRES_DB}
      PGRST_DB_SCHEMAS: public,storage,graphql_public
      PGRST_DB_ANON_ROLE: anon
      PGRST_JWT_SECRET: \${JWT_SECRET}
      PGRST_DB_USE_LEGACY_GUCS: false
      PGRST_APP_SETTINGS_JWT_SECRET: \${JWT_SECRET}
      PGRST_APP_SETTINGS_JWT_EXP: \${GOTRUE_JWT_EXP}
    networks:
      - ${PRIVATE_TIER}
    depends_on:
      supabase-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase Realtime
  supabase-realtime:
    image: supabase/realtime:v2.25.50
    container_name: supabase-realtime
    restart: unless-stopped
    environment:
      PORT: 4000
      DB_HOST: supabase-db
      DB_PORT: 5432
      DB_USER: \${POSTGRES_USER}
      DB_PASSWORD: \${POSTGRES_PASSWORD}
      DB_NAME: \${POSTGRES_DB}
      DB_AFTER_CONNECT_QUERY: 'SET search_path TO _realtime'
      DB_ENC_KEY: \${REALTIME_DB_ENC_KEY}
      API_JWT_SECRET: \${JWT_SECRET}
      FLY_ALLOC_ID: fly123
      FLY_APP_NAME: realtime
      SECRET_KEY_BASE: \${JWT_SECRET}
      ERL_AFLAGS: -proto_dist inet_tcp
      ENABLE_TAILSCALE: false
      DNS_NODES: "''"
    networks:
      - ${PRIVATE_TIER}
    depends_on:
      supabase-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:4000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase Storage
  supabase-storage:
    image: supabase/storage-api:v1.0.6
    container_name: supabase-storage
    restart: unless-stopped
    environment:
      ANON_KEY: \${ANON_KEY}
      SERVICE_KEY: \${SERVICE_ROLE_KEY}
      POSTGREST_URL: http://supabase-rest:3000
      PGRST_JWT_SECRET: \${JWT_SECRET}
      DATABASE_URL: postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@supabase-db:5432/\${POSTGRES_DB}
      FILE_SIZE_LIMIT: \${STORAGE_FILE_SIZE_LIMIT}
      STORAGE_BACKEND: \${STORAGE_BACKEND}
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
      TENANT_ID: stub
      REGION: us-east-1
      GLOBAL_S3_BUCKET: stub
      ENABLE_IMAGE_TRANSFORMATION: true
      IMGPROXY_URL: http://supabase-imgproxy:5001
    volumes:
      - supabase_storage_data:/var/lib/storage
    networks:
      - ${PRIVATE_TIER}
    depends_on:
      supabase-db:
        condition: service_healthy
      supabase-rest:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5000/status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase Image Proxy
  supabase-imgproxy:
    image: darthsim/imgproxy:v3.18.2
    container_name: supabase-imgproxy
    restart: unless-stopped
    environment:
      IMGPROXY_BIND: "0.0.0.0:5001"
      IMGPROXY_LOCAL_FILESYSTEM_ROOT: /
      IMGPROXY_USE_ETAG: true
      IMGPROXY_ENABLE_WEBP_DETECTION: true
    volumes:
      - supabase_storage_data:/var/lib/storage:ro
    networks:
      - ${PRIVATE_TIER}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase Studio
  supabase-studio:
    image: supabase/studio:20240326-5e5586d
    container_name: supabase-studio
    restart: unless-stopped
    environment:
      STUDIO_PG_META_URL: http://supabase-meta:8080
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      DEFAULT_ORGANIZATION_NAME: \${ORGANIZATION}
      DEFAULT_PROJECT_NAME: JStack
      SUPABASE_URL: \${API_EXTERNAL_URL}
      SUPABASE_ANON_KEY: \${ANON_KEY}
      SUPABASE_SERVICE_KEY: \${SERVICE_ROLE_KEY}
      LOGFLARE_API_KEY: \${LOGFLARE_API_KEY}
      LOGFLARE_URL: https://api.logflare.app
      NEXT_PUBLIC_ENABLE_LOGS: true
    networks:
      - ${PRIVATE_TIER}
      - ${PUBLIC_TIER}
    ports:
      - "${SUPABASE_STUDIO_PORT}:3000"
    depends_on:
      supabase-meta:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # Supabase Meta
  supabase-meta:
    image: supabase/postgres-meta:v0.68.0
    container_name: supabase-meta
    restart: unless-stopped
    environment:
      PG_META_PORT: 8080
      PG_META_DB_HOST: supabase-db
      PG_META_DB_PORT: 5432
      PG_META_DB_NAME: \${POSTGRES_DB}
      PG_META_DB_USER: \${POSTGRES_USER}
      PG_META_DB_PASSWORD: \${POSTGRES_PASSWORD}
    networks:
      - ${PRIVATE_TIER}
    depends_on:
      supabase-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

networks:
  ${PUBLIC_TIER}:
    external: true
  ${PRIVATE_TIER}:
    external: true

volumes:
  supabase_db_data:
    driver: local
  supabase_storage_data:
    driver: local
EOF
    
    safe_mv "/tmp/docker-compose.yml" "$supabase_dir/docker-compose.yml" "Install Supabase compose"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$supabase_dir/docker-compose.yml" "Set compose ownership"
    
    # Create Kong configuration directory and file
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $supabase_dir/config" "Create Supabase config directory"
    
    cat > /tmp/kong.yml << 'EOF'
_format_version: "3.0"
_transform: true

services:
  - name: auth-v1-open
    url: http://supabase-auth:9999/verify
    plugins:
      - name: cors
  - name: auth-v1-open-callback
    url: http://supabase-auth:9999/callback
    plugins:
      - name: cors
  - name: auth-v1-open-authorize
    url: http://supabase-auth:9999/authorize
    plugins:
      - name: cors

  - name: auth-v1
    _comment: "GoTrue: /auth/v1/* -> http://supabase-auth:9999/*"
    url: http://supabase-auth:9999/
    routes:
      - name: auth-v1-all
        strip_path: true
        paths:
          - /auth/v1/
    plugins:
      - name: cors

  - name: rest-v1
    _comment: "PostgREST: /rest/v1/* -> http://supabase-rest:3000/*"
    url: http://supabase-rest:3000/
    routes:
      - name: rest-v1-all
        strip_path: true
        paths:
          - /rest/v1/
    plugins:
      - name: cors

  - name: realtime-v1
    _comment: "Realtime: /realtime/v1/* -> ws://supabase-realtime:4000/socket/*"
    url: http://supabase-realtime:4000/socket/
    routes:
      - name: realtime-v1-all
        strip_path: true
        paths:
          - /realtime/v1/
    plugins:
      - name: cors

  - name: storage-v1
    _comment: "Storage: /storage/v1/* -> http://supabase-storage:5000/*"
    url: http://supabase-storage:5000/
    routes:
      - name: storage-v1-all
        strip_path: true
        paths:
          - /storage/v1/
    plugins:
      - name: cors

consumers: []

plugins:
  - name: cors
    config:
      origins:
        - "*"
      methods:
        - GET
        - HEAD
        - PUT
        - PATCH
        - POST
        - DELETE
        - OPTIONS
        - TRACE
        - CONNECT
      headers:
        - Accept
        - Accept-Version
        - Content-Length
        - Content-MD5
        - Content-Type
        - Date
        - Authorization
        - X-Requested-With
        - apikey
        - prefer
        - range
      exposed_headers:
        - Content-Length
        - Content-Range
        - X-Requested-With
      credentials: true
      max_age: 3600
EOF
    
    safe_mv "/tmp/kong.yml" "$supabase_dir/config/kong.yml" "Install Kong config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$supabase_dir/config/kong.yml" "Set Kong config ownership"
    
    # Start Supabase services
    log_info "Starting Supabase services"
    docker_cmd "cd $supabase_dir && docker-compose --env-file .env up -d" "Start Supabase containers"
    
    # Wait for database to be ready and initialize
    wait_for_service_health "supabase-db" 120 10
    
    # Initialize database schemas and setup
    log_info "Initializing database with proper schemas and users"
    if bash "${PROJECT_ROOT}/scripts/core/database_init.sh" complete; then
        log_success "Database initialization completed successfully"
    else
        log_error "Database initialization failed"
        return 1
    fi
    
    # Wait for remaining services to be healthy
    wait_for_service_health "supabase-auth" 60 5
    wait_for_service_health "supabase-rest" 60 5
    wait_for_service_health "supabase-studio" 60 5
    
    end_section_timer "Supabase Setup"
    log_success "Supabase containers setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN SERVICE ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-setup}" in
        "setup"|"deploy")
            setup_supabase_containers
            ;;
        "status")
            log_info "Checking Supabase service status"
            docker ps --filter name=supabase- --format "table {{.Names}}\\t{{.Status}}"
            ;;
        "logs")
            service_name="${2:-supabase-db}"
            log_info "Showing logs for: $service_name"
            docker logs "$service_name"
            ;;
        *)
            echo "Usage: $0 [setup|status|logs [service-name]]"
            echo "Services: supabase-db, supabase-kong, supabase-auth, supabase-rest,"
            echo "         supabase-realtime, supabase-storage, supabase-imgproxy,"
            echo "         supabase-studio, supabase-meta"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi