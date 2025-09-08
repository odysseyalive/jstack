#!/bin/bash
# Container orchestration for COMPASS Stack
# Handles Supabase, N8N, NGINX, and site management

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
    
    if [[ "$DRY_RUN" == "true" ]]; then
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
# Supabase Configuration for COMPASS Stack
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
      DEFAULT_PROJECT_NAME: COMPASS Stack
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
# 🤖 BROWSER AUTOMATION SETUP (Debian 12 Headless Chrome)
# ═══════════════════════════════════════════════════════════════════════════════

install_chrome_dependencies() {
    log_section "Installing Chrome Dependencies for Debian 12"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Chrome dependencies"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping Chrome installation"
        return 0
    fi
    
    start_section_timer "Chrome Dependencies"
    
    # Update package index
    execute_cmd "apt-get update" "Update package index"
    
    # Install required dependencies for Chrome on Debian 12
    log_info "Installing Chrome system dependencies"
    execute_cmd "apt-get install -y wget gnupg ca-certificates apt-transport-https software-properties-common" "Install base dependencies"
    
    # Add Google Chrome repository
    log_info "Adding Google Chrome repository"
    execute_cmd "wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg" "Add Google signing key"
    execute_cmd "echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] ${CHROME_REPOSITORY} stable main' > /etc/apt/sources.list.d/google-chrome.list" "Add Chrome repository"
    
    # Update package index with new repository
    execute_cmd "apt-get update" "Update with Chrome repository"
    
    # Install Chrome and required dependencies for headless operation
    log_info "Installing Google Chrome and headless dependencies"
    execute_cmd "apt-get install -y ${CHROME_PACKAGE} ${CHROME_DEPENDENCIES}" "Install Chrome and dependencies"
    
    # Install additional fonts for better rendering
    execute_cmd "apt-get install -y fonts-noto fonts-noto-color-emoji fonts-dejavu-core" "Install additional fonts"
    
    # Verify Chrome installation
    if chrome_version=$(google-chrome --version 2>/dev/null); then
        log_success "Chrome installed successfully: $chrome_version"
    else
        log_error "Chrome installation verification failed"
        return 1
    fi
    
    end_section_timer "Chrome Dependencies"
    log_success "Chrome dependencies installed successfully"
}

setup_puppeteer_environment() {
    log_section "Setting up Puppeteer Environment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Puppeteer environment"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping Puppeteer setup"
        return 0
    fi
    
    start_section_timer "Puppeteer Setup"
    
    # Create Puppeteer cache directory
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $PUPPETEER_CACHE_DIR" "Create Puppeteer cache directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $PUPPETEER_CACHE_DIR/screenshots" "Create screenshots directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $PUPPETEER_CACHE_DIR/pdfs" "Create PDFs directory"
    
    # Set proper permissions
    safe_chmod "755" "$PUPPETEER_CACHE_DIR" "Set Puppeteer cache permissions"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$PUPPETEER_CACHE_DIR" "Set Puppeteer cache ownership"
    
    # Create Puppeteer configuration file
    cat > /tmp/puppeteer-config.json << EOF
{
  "executablePath": "${PUPPETEER_EXECUTABLE_PATH}",
  "downloadHost": "${PUPPETEER_DOWNLOAD_HOST}",
  "skipChromiumDownload": ${PUPPETEER_SKIP_CHROMIUM_DOWNLOAD},
  "cacheDirectory": "${PUPPETEER_CACHE_DIR}",
  "defaultArgs": [
    $(echo "$CHROME_SECURITY_ARGS" | sed 's/ /",
    "/g' | sed 's/^/    "/' | sed 's/$/"/'),
    "--disable-web-security",
    "--allow-running-insecure-content",
    "--disable-features=TranslateUI",
    "--disable-ipc-flooding-protection",
    "--no-first-run",
    "--no-default-browser-check"
  ],
  "headless": "new",
  "defaultViewport": {
    "width": 1920,
    "height": 1080
  },
  "timeout": ${CHROME_INSTANCE_TIMEOUT}000
}
EOF
    
    safe_mv "/tmp/puppeteer-config.json" "$PUPPETEER_CACHE_DIR/config.json" "Install Puppeteer config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$PUPPETEER_CACHE_DIR/config.json" "Set Puppeteer config ownership"
    
    # Test Chrome headless functionality
    log_info "Testing Chrome headless functionality"
    if sudo -u $SERVICE_USER google-chrome --headless=new --disable-gpu --no-sandbox --dump-dom about:blank > /dev/null 2>&1; then
        log_success "Chrome headless test passed"
    else
        log_error "Chrome headless test failed"
        return 1
    fi
    
    end_section_timer "Puppeteer Setup"
    log_success "Puppeteer environment setup completed"
}

create_browser_automation_monitoring() {
    log_section "Creating Browser Automation Monitoring"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create browser automation monitoring"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping monitoring setup"
        return 0
    fi
    
    start_section_timer "Browser Monitoring"
    
    # Create monitoring script
    cat > /tmp/browser-monitor.sh << 'EOF'
#!/bin/bash
# Browser Automation Monitoring Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

monitor_chrome_processes() {
    local chrome_count=$(pgrep -f "google-chrome" | wc -l)
    local max_instances=${CHROME_MAX_INSTANCES:-5}
    
    if [[ $chrome_count -gt $max_instances ]]; then
        log_warning "Chrome process count ($chrome_count) exceeds limit ($max_instances)"
        
        # Kill oldest Chrome processes if too many
        log_info "Cleaning up excess Chrome processes"
        pkill -f --oldest "google-chrome.*--headless" || true
    fi
    
    # Monitor memory usage
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $total_memory -gt 90 ]]; then
        log_warning "High memory usage detected: ${total_memory}%"
        cleanup_browser_cache
    fi
    
    log_info "Chrome processes: $chrome_count, Memory usage: ${total_memory}%"
}

cleanup_browser_cache() {
    log_info "Cleaning up browser cache and temporary files"
    
    # Clean Puppeteer cache (keep last 100 screenshots/PDFs)
    find "$PUPPETEER_CACHE_DIR/screenshots" -type f -mtime +1 -exec rm {} \; 2>/dev/null || true
    find "$PUPPETEER_CACHE_DIR/pdfs" -type f -mtime +1 -exec rm {} \; 2>/dev/null || true
    
    # Clean Chrome temporary files
    find /tmp -name "chrome_*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -name ".org.chromium.*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    log_success "Browser cache cleanup completed"
}

# Main monitoring function
case "${1:-monitor}" in
    "monitor")
        monitor_chrome_processes
        ;;
    "cleanup")
        cleanup_browser_cache
        ;;
    *)
        echo "Usage: $0 [monitor|cleanup]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/browser-monitor.sh" "$BASE_DIR/scripts/browser-monitor.sh" "Install browser monitor script"
    safe_chmod "755" "$BASE_DIR/scripts/browser-monitor.sh" "Make browser monitor executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-monitor.sh" "Set browser monitor ownership"
    
    # Create systemd timer for browser monitoring (optional)
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/browser-monitor.service << EOF
[Unit]
Description=Browser Automation Monitoring
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/browser-monitor.sh monitor
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/browser-monitor.timer << EOF
[Unit]
Description=Run Browser Monitoring every hour
Requires=browser-monitor.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/browser-monitor.service" "/etc/systemd/system/browser-monitor.service" "Install monitor service"
        safe_mv "/tmp/browser-monitor.timer" "/etc/systemd/system/browser-monitor.timer" "Install monitor timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd"
        execute_cmd "systemctl enable browser-monitor.timer" "Enable browser monitor timer"
        execute_cmd "systemctl start browser-monitor.timer" "Start browser monitor timer"
    fi
    
    end_section_timer "Browser Monitoring"
    log_success "Browser automation monitoring created successfully"
}

test_browser_automation_integration() {
    log_section "Testing Browser Automation Integration"
    
    if [[ "\$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test browser automation integration"
        return 0
    fi
    
    start_section_timer "Browser Integration Test"
    
    # Test Chrome availability in N8N container
    log_info "Testing Chrome availability in N8N container"
    if docker_cmd "docker exec n8n google-chrome --version" "Check Chrome in N8N container"; then
        log_success "Chrome is available in N8N container"
    else
        log_warning "Chrome may not be properly mounted in N8N container"
    fi
    
    # Test Puppeteer directories
    log_info "Testing Puppeteer directories"
    if docker_cmd "docker exec n8n ls -la \${PUPPETEER_CACHE_DIR}" "Check Puppeteer cache directory"; then
        log_success "Puppeteer cache directory is accessible"
    else
        log_warning "Puppeteer cache directory may not be properly mounted"
    fi
    
    # Test basic headless Chrome functionality in container
    log_info "Testing headless Chrome in N8N container"
    if docker_cmd "docker exec n8n google-chrome --headless=new --disable-gpu --no-sandbox --dump-dom about:blank" "Test headless Chrome"; then
        log_success "Headless Chrome test passed in N8N container"
    else
        log_warning "Headless Chrome test failed - may require troubleshooting"
    fi
    
    end_section_timer "Browser Integration Test"
    log_success "Browser automation integration testing completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 N8N CONTAINER SETUP (Enhanced with Browser Automation)
# ═══════════════════════════════════════════════════════════════════════════════

setup_n8n_container() {
    log_section "Setting up N8N Container"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup N8N container"
        return 0
    fi
    
    start_section_timer "N8N Setup"
    
    # Setup browser automation if enabled
    if [[ "\$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        log_info "Setting up secure browser automation"
        if bash "${PROJECT_ROOT}/scripts/core/secure_browser.sh" setup; then
            log_success "Secure browser automation configured"
        else
            log_warning "Secure browser automation setup failed - continuing without browser support"
        fi
    fi
    
    local n8n_dir="\$BASE_DIR/services/n8n"
    execute_cmd "sudo -u \$SERVICE_USER mkdir -p \$n8n_dir" "Create N8N directory"
    
    # Generate N8N encryption key
    local n8n_encryption_key=$(generate_secret)
    
    # Create N8N environment file
    cat > /tmp/n8n.env << EOF
# N8N Configuration for COMPASS Stack
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}
WEBHOOK_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}

# Database Configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=supabase-db
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=$(generate_password)

# Security
N8N_ENCRYPTION_KEY=$n8n_encryption_key
N8N_USER_MANAGEMENT_DISABLED=true
N8N_BASIC_AUTH_ACTIVE=false
N8N_JWT_AUTH_ACTIVE=true
N8N_JWKS_URI=
N8N_JWT_AUTH_HEADER=authorization
N8N_JWT_AUTH_HEADER_VALUE_PREFIX=Bearer

# Execution
EXECUTIONS_TIMEOUT=${N8N_EXECUTION_TIMEOUT}
EXECUTIONS_TIMEOUT_MAX=${N8N_EXECUTION_TIMEOUT}
EXECUTIONS_DATA_MAX_AGE=${N8N_MAX_EXECUTION_HISTORY}
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_PRUNE_MAX_AGE=${N8N_MAX_EXECUTION_HISTORY}

# Performance
N8N_CONCURRENCY_PRODUCTION=10
N8N_PAYLOAD_SIZE_MAX=16

# Logging
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_LOG_FILE_LOCATION=/home/node/.n8n/logs/

# Timezone
GENERIC_TIMEZONE=${N8N_TIMEZONE}
TZ=${N8N_TIMEZONE}

# Features
N8N_DIAGNOSTICS_ENABLED=false
N8N_VERSION_NOTIFICATIONS_ENABLED=false
N8N_TEMPLATES_ENABLED=true
N8N_PUBLIC_API_DISABLED=false
N8N_ONBOARDING_FLOW_DISABLED=true

# External Services
N8N_HIRING_BANNER_ENABLED=false
N8N_METRICS=false
N8N_BINARY_DATA_MODE=filesystem

# Custom Nodes
N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom
EXTERNAL_FRONTEND_HOOKS_URLS=
EXTERNAL_HOOK_FILES=

# Advanced
N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=false
N8N_GRACEFUL_SHUTDOWN_TIMEOUT=30
EOF
    
    safe_mv "/tmp/n8n.env" "$n8n_dir/.env" "Install N8N environment"
    safe_chmod "600" "$n8n_dir/.env" "Secure N8N environment"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$n8n_dir/.env" "Set N8N env ownership"
    
    # Create N8N Docker Compose with Browser Automation Support
    cat > /tmp/docker-compose.yml << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:1.31.2
    container_name: n8n
    restart: unless-stopped
    user: root
    environment:
      - N8N_HOST=\${N8N_HOST}
      - N8N_PORT=\${N8N_PORT}
      - N8N_PROTOCOL=\${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=\${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=\${WEBHOOK_URL}
      - DB_TYPE=\${DB_TYPE}
      - DB_POSTGRESDB_HOST=\${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=\${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=\${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=\${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=\${DB_POSTGRESDB_PASSWORD}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_DISABLED=\${N8N_USER_MANAGEMENT_DISABLED}
      - N8N_BASIC_AUTH_ACTIVE=\${N8N_BASIC_AUTH_ACTIVE}
      - EXECUTIONS_TIMEOUT=\${EXECUTIONS_TIMEOUT}
      - EXECUTIONS_TIMEOUT_MAX=\${EXECUTIONS_TIMEOUT_MAX}
      - EXECUTIONS_DATA_MAX_AGE=\${EXECUTIONS_DATA_MAX_AGE}
      - EXECUTIONS_DATA_PRUNE=\${EXECUTIONS_DATA_PRUNE}
      - EXECUTIONS_DATA_PRUNE_MAX_AGE=\${EXECUTIONS_DATA_PRUNE_MAX_AGE}
      - N8N_CONCURRENCY_PRODUCTION=\${N8N_CONCURRENCY_PRODUCTION}
      - N8N_PAYLOAD_SIZE_MAX=\${N8N_PAYLOAD_SIZE_MAX}
      - N8N_LOG_LEVEL=\${N8N_LOG_LEVEL}
      - N8N_LOG_OUTPUT=\${N8N_LOG_OUTPUT}
      - N8N_LOG_FILE_LOCATION=\${N8N_LOG_FILE_LOCATION}
      - GENERIC_TIMEZONE=\${GENERIC_TIMEZONE}
      - TZ=\${TZ}
      - N8N_DIAGNOSTICS_ENABLED=\${N8N_DIAGNOSTICS_ENABLED}
      - N8N_VERSION_NOTIFICATIONS_ENABLED=\${N8N_VERSION_NOTIFICATIONS_ENABLED}
      - N8N_TEMPLATES_ENABLED=\${N8N_TEMPLATES_ENABLED}
      - N8N_PUBLIC_API_DISABLED=\${N8N_PUBLIC_API_DISABLED}
      - N8N_ONBOARDING_FLOW_DISABLED=\${N8N_ONBOARDING_FLOW_DISABLED}
      - N8N_HIRING_BANNER_ENABLED=\${N8N_HIRING_BANNER_ENABLED}
      - N8N_METRICS=\${N8N_METRICS}
      - N8N_BINARY_DATA_MODE=\${N8N_BINARY_DATA_MODE}
      - N8N_CUSTOM_EXTENSIONS=\${N8N_CUSTOM_EXTENSIONS}
      - N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=\${N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN}
      - N8N_GRACEFUL_SHUTDOWN_TIMEOUT=\\${N8N_GRACEFUL_SHUTDOWN_TIMEOUT}
      # Browser Automation Environment Variables
      - PUPPETEER_EXECUTABLE_PATH=\\${PUPPETEER_EXECUTABLE_PATH}
      - PUPPETEER_CACHE_DIR=\\${PUPPETEER_CACHE_DIR}
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=\\${PUPPETEER_SKIP_CHROMIUM_DOWNLOAD}
      - CHROME_ARGS=\\${CHROME_SECURITY_ARGS}
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_custom:/home/node/.n8n/custom
      - n8n_logs:/home/node/.n8n/logs
      - n8n_puppeteer:\${PUPPETEER_CACHE_DIR}
      # Mount Chrome from host system
      - /usr/bin/google-chrome:\${PUPPETEER_EXECUTABLE_PATH}:ro
      - /usr/share/fonts:/usr/share/fonts:ro
      - /dev/shm:/dev/shm
    ports:
      - "${N8N_PORT}:5678"
    networks:
      - ${PUBLIC_TIER}
      - ${PRIVATE_TIER}
    external_links:
      - supabase-db:supabase-db
    deploy:
      resources:
        limits:
          memory: \${CHROME_MEMORY_LIMIT}
          cpus: '\${CHROME_CPU_LIMIT}'
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
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
  n8n_data:
    driver: local
  n8n_custom:
    driver: local
  n8n_logs:
    driver: local
  n8n_puppeteer:
    driver: local
EOF
    
    safe_mv "/tmp/docker-compose.yml" "$n8n_dir/docker-compose.yml" "Install N8N compose"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$n8n_dir/docker-compose.yml" "Set N8N compose ownership"
    
    # N8N database is now handled by database_init.sh during Supabase setup
    log_info "N8N database and user configuration handled by database initialization"
    docker_cmd "docker exec supabase-db psql -U postgres -c \"CREATE DATABASE n8n;\"" "Create N8N database" || true
    docker_cmd "docker exec supabase-db psql -U postgres -c \"CREATE USER n8n_user WITH PASSWORD '$(grep DB_POSTGRESDB_PASSWORD $n8n_dir/.env | cut -d= -f2)';\"" "Create N8N user" || true
    docker_cmd "docker exec supabase-db psql -U postgres -c \"GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;\"" "Grant N8N permissions" || true
    
    # Start N8N service
    log_info "Starting N8N service"
    docker_cmd "cd $n8n_dir && docker-compose --env-file .env up -d" "Start N8N container"
    
    # Wait for N8N to be healthy
    wait_for_service_health "n8n" 120 10
    
    # Test browser automation integration if enabled
    if [[ "\$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        log_info "Testing secure browser automation integration"
        bash "${PROJECT_ROOT}/scripts/core/secure_browser.sh" test || true
    fi
    
    end_section_timer "N8N Setup"
    log_success "N8N container setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 NGINX CONTAINER SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_nginx_container() {
    log_section "Setting up NGINX Container"
    
    if [[ "$DRY_RUN" == "true" ]]; then
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
    
    # Create Supabase Studio configuration
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
    
    # Create N8N configuration
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
    
    # Set ownership for all config files
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$nginx_dir/conf/" "Set NGINX configs ownership"
    
    # Create NGINX Docker Compose
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
    
    # NGINX will be started by the SSL setup script after certificates are ready
    
    end_section_timer "NGINX Setup"
    log_success "NGINX container setup completed (ready for SSL)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN CONTAINERS ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Deploy all containers
deploy_all_containers() {
    log_section "Deploying All Containers"
    
    # Initialize timing
    init_timing_system
    
    # Deploy containers in order
    if setup_supabase_containers && \
       setup_n8n_container && \
       setup_nginx_container; then
        
        log_success "All containers deployed successfully"
        return 0
    else
        log_error "Container deployment failed"
        return 1
    fi
}

# Main function for testing
main() {
    case "${1:-deploy}" in
        "deploy"|"all")
            deploy_all_containers
            ;;
        "supabase")
            setup_supabase_containers
            ;;
        "n8n")
            setup_n8n_container
            ;;
        "nginx")
            setup_nginx_container
            ;;
        *)
            echo "Usage: $0 [deploy|supabase|n8n|nginx]"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi