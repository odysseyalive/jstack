#!/bin/bash
# Secure Browser Automation for COMPASS Stack
# Implements containerized Chrome with proper security constraints

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔒 SECURE CHROME CONTAINER SETUP
# ═══════════════════════════════════════════════════════════════════════════════

# Create secure Chrome container configuration
create_secure_chrome_container() {
    log_section "Creating Secure Chrome Container Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create secure Chrome container configuration"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping secure Chrome setup"
        return 0
    fi
    
    start_section_timer "Secure Chrome Setup"
    
    local chrome_dir="$BASE_DIR/services/chrome"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $chrome_dir" "Create Chrome service directory"
    
    # Create secure Chrome Docker Compose
    cat > /tmp/chrome-docker-compose.yml << EOF
version: '3.8'

services:
  chrome:
    image: zenika/alpine-chrome:123-with-chromedriver-selenoid
    container_name: jarvis-chrome
    restart: unless-stopped
    command: [
      "--headless", 
      "--disable-gpu", 
      "--disable-dev-shm-usage",
      "--remote-debugging-address=0.0.0.0", 
      "--remote-debugging-port=9222",
      "--disable-extensions",
      "--disable-plugins", 
      "--disable-background-timer-throttling",
      "--disable-renderer-backgrounding", 
      "--disable-default-apps",
      "--disable-sync", 
      "--disable-translate", 
      "--hide-scrollbars", 
      "--mute-audio",
      "--disable-background-networking",
      "--disable-features=TranslateUI",
      "--disable-ipc-flooding-protection",
      "--no-first-run",
      "--no-default-browser-check",
      "--window-size=1920,1080"
    ]
    networks:
      - ${PRIVATE_TIER}
    deploy:
      resources:
        limits:
          memory: ${CHROME_MEMORY_LIMIT}
          cpus: '${CHROME_CPU_LIMIT}'
        reservations:
          memory: 512M
    # Security hardening
    security_opt:
      - no-new-privileges:true
      - seccomp:unconfined  # Required for Chrome to function properly
    cap_drop:
      - ALL
    cap_add:
      - SYS_ADMIN  # Required for Chrome sandbox
    tmpfs:
      - /tmp:size=1G,noexec,nosuid,nodev
      - /dev/shm:size=2G,rw,noexec,nosuid,nodev
    volumes:
      - chrome_data:/data
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9222/json/version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    environment:
      - CHROME_OPTS=--remote-debugging-address=0.0.0.0 --remote-debugging-port=9222
    labels:
      - "com.jarvisstack.service=chrome"
      - "com.jarvisstack.security=hardened"

networks:
  ${PRIVATE_TIER}:
    external: true

volumes:
  chrome_data:
    driver: local
EOF
    
    safe_mv "/tmp/chrome-docker-compose.yml" "$chrome_dir/docker-compose.yml" "Install Chrome compose"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$chrome_dir/docker-compose.yml" "Set Chrome compose ownership"
    
    # Create Chrome service management script
    cat > /tmp/chrome-service.sh << 'EOF'
#!/bin/bash
# Chrome Service Management Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

CHROME_DIR="$BASE_DIR/services/chrome"

start_chrome() {
    log_info "Starting secure Chrome container"
    if docker_cmd "cd $CHROME_DIR && docker-compose up -d" "Start Chrome container"; then
        wait_for_service_health "jarvis-chrome" 60 5
        log_success "Chrome container started successfully"
    else
        log_error "Failed to start Chrome container"
        return 1
    fi
}

stop_chrome() {
    log_info "Stopping Chrome container"
    docker_cmd "cd $CHROME_DIR && docker-compose down" "Stop Chrome container"
    log_success "Chrome container stopped"
}

restart_chrome() {
    log_info "Restarting Chrome container"
    stop_chrome
    start_chrome
}

status_chrome() {
    log_info "Chrome container status"
    
    if docker ps --filter "name=jarvis-chrome" --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
        echo "Chrome container: Running"
        
        # Test remote debugging endpoint
        if curl -s http://localhost:9222/json/version >/dev/null 2>&1; then
            echo "Remote debugging: Available"
        else
            echo "Remote debugging: Not available"
        fi
        
        # Show resource usage
        docker stats jarvis-chrome --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true
    else
        echo "Chrome container: Not running"
    fi
}

case "${1:-status}" in
    "start")
        start_chrome
        ;;
    "stop")
        stop_chrome
        ;;
    "restart")
        restart_chrome
        ;;
    "status")
        status_chrome
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|status]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/chrome-service.sh" "$chrome_dir/chrome-service.sh" "Install Chrome service script"
    safe_chmod "755" "$chrome_dir/chrome-service.sh" "Make Chrome service executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$chrome_dir/chrome-service.sh" "Set Chrome service ownership"
    
    end_section_timer "Secure Chrome Setup"
    log_success "Secure Chrome container configuration created"
    return 0
}

# Update N8N configuration for secure Chrome integration
update_n8n_chrome_integration() {
    log_section "Updating N8N for Secure Chrome Integration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update N8N Chrome integration"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping N8N Chrome integration"
        return 0
    fi
    
    start_section_timer "N8N Chrome Integration"
    
    local n8n_dir="$BASE_DIR/services/n8n"
    
    if [[ ! -f "$n8n_dir/docker-compose.yml" ]]; then
        log_error "N8N docker-compose.yml not found"
        return 1
    fi
    
    # Backup existing N8N configuration
    cp "$n8n_dir/docker-compose.yml" "$n8n_dir/docker-compose.yml.backup"
    
    # Update N8N environment for secure Chrome
    log_info "Updating N8N environment for secure Chrome integration"
    
    # Add/update Chrome-related environment variables in N8N .env file
    local n8n_env_file="$n8n_dir/.env"
    
    if [[ -f "$n8n_env_file" ]]; then
        # Remove old Chrome configuration
        sed -i '/PUPPETEER_EXECUTABLE_PATH/d' "$n8n_env_file"
        sed -i '/CHROME_ARGS/d' "$n8n_env_file"
        sed -i '/PUPPETEER_SKIP_CHROMIUM_DOWNLOAD/d' "$n8n_env_file"
        
        # Add secure Chrome configuration
        cat >> "$n8n_env_file" << EOF

# Secure Chrome Integration
CHROME_WS_ENDPOINT=ws://jarvis-chrome:9222
PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=false
CHROME_DISABLE_SANDBOX=false
EOF
        
        log_success "N8N environment updated for secure Chrome"
    else
        log_warning "N8N environment file not found"
    fi
    
    # Update N8N docker-compose to depend on Chrome service
    log_info "Adding Chrome dependency to N8N service"
    
    # Add Chrome service dependency to N8N
    if ! grep -q "depends_on:" "$n8n_dir/docker-compose.yml"; then
        # Add depends_on section
        sed -i '/external_links:/i \    depends_on:\n      - chrome\n    external_links:' "$n8n_dir/docker-compose.yml"
    else
        # Add chrome to existing depends_on
        if ! grep -q "chrome" "$n8n_dir/docker-compose.yml"; then
            sed -i '/depends_on:/a \      - chrome' "$n8n_dir/docker-compose.yml"
        fi
    fi
    
    # Add Chrome service reference
    cat >> "$n8n_dir/docker-compose.yml" << EOF

  # Chrome service reference (managed separately)
  chrome:
    image: zenika/alpine-chrome:123-with-chromedriver-selenoid
    external: true
    container_name: jarvis-chrome
EOF
    
    end_section_timer "N8N Chrome Integration"
    log_success "N8N Chrome integration updated"
    return 0
}

# Create secure browser automation monitoring
create_secure_browser_monitoring() {
    log_section "Creating Secure Browser Automation Monitoring"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create secure browser monitoring"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping monitoring setup"
        return 0
    fi
    
    start_section_timer "Secure Browser Monitoring"
    
    # Create enhanced monitoring script with security focus
    cat > /tmp/secure-browser-monitor.sh << 'EOF'
#!/bin/bash
# Secure Browser Automation Monitoring Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

monitor_chrome_security() {
    log_info "Monitoring Chrome container security and performance"
    
    # Check if Chrome container is running
    if ! docker ps --filter "name=jarvis-chrome" --format "{{.Names}}" | grep -q "jarvis-chrome"; then
        log_warning "Chrome container not running"
        return 1
    fi
    
    # Security monitoring
    log_info "Chrome Security Status:"
    
    # Check security options
    local security_opts=$(docker inspect jarvis-chrome --format '{{range .HostConfig.SecurityOpt}}{{.}} {{end}}' 2>/dev/null)
    if [[ "$security_opts" == *"no-new-privileges:true"* ]]; then
        echo "  ✓ no-new-privileges enabled"
    else
        echo "  ❌ no-new-privileges not enabled"
    fi
    
    # Check capabilities
    local cap_drop=$(docker inspect jarvis-chrome --format '{{.HostConfig.CapDrop}}' 2>/dev/null)
    if [[ "$cap_drop" == *"ALL"* ]]; then
        echo "  ✓ All capabilities dropped"
    else
        echo "  ⚠️  Not all capabilities dropped"
    fi
    
    # Resource monitoring
    log_info "Chrome Resource Usage:"
    docker stats jarvis-chrome --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "  Unable to get stats"
    
    # Health check
    if curl -s --max-time 5 http://localhost:9222/json/version >/dev/null 2>&1; then
        echo "  ✓ Remote debugging endpoint healthy"
    else
        echo "  ❌ Remote debugging endpoint not accessible"
    fi
    
    # Check for security violations in logs
    local security_violations=$(docker logs jarvis-chrome --since 1h 2>&1 | grep -i -E "(security|violation|sandbox|privilege)" | wc -l)
    if [[ $security_violations -gt 0 ]]; then
        echo "  ⚠️  $security_violations security-related log entries found in last hour"
    else
        echo "  ✓ No security violations detected in logs"
    fi
}

cleanup_chrome_resources() {
    log_info "Cleaning up Chrome resources and temporary files"
    
    # Clean up Chrome data volume if it gets too large
    local chrome_volume_size=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" | grep -i volume | awk '{print $3}' | head -n1)
    log_info "Chrome data volume size: ${chrome_volume_size:-unknown}"
    
    # Restart Chrome if memory usage is too high
    local mem_usage=$(docker stats jarvis-chrome --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//')
    if [[ -n "$mem_usage" ]] && [[ $(echo "$mem_usage > 80" | bc -l) -eq 1 ]]; then
        log_warning "Chrome memory usage high ($mem_usage%) - restarting container"
        docker restart jarvis-chrome
    fi
    
    # Clean up any orphaned Chrome processes (shouldn't exist in containerized setup)
    local host_chrome_processes=$(pgrep -f "google-chrome|chromium" | wc -l)
    if [[ $host_chrome_processes -gt 0 ]]; then
        log_warning "Found $host_chrome_processes Chrome processes running on host - this may be a security concern"
    fi
}

# Main monitoring function
case "${1:-monitor}" in
    "monitor")
        monitor_chrome_security
        ;;
    "cleanup")
        cleanup_chrome_resources
        ;;
    "security")
        monitor_chrome_security
        ;;
    *)
        echo "Usage: $0 [monitor|cleanup|security]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/secure-browser-monitor.sh" "$BASE_DIR/scripts/secure-browser-monitor.sh" "Install secure browser monitor"
    safe_chmod "755" "$BASE_DIR/scripts/secure-browser-monitor.sh" "Make secure browser monitor executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/secure-browser-monitor.sh" "Set secure browser monitor ownership"
    
    # Create systemd timer for secure browser monitoring
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/secure-browser-monitor.service << EOF
[Unit]
Description=Secure Browser Automation Monitoring
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/secure-browser-monitor.sh monitor
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/secure-browser-monitor.timer << EOF
[Unit]
Description=Run Secure Browser Monitoring every 30 minutes
Requires=secure-browser-monitor.service

[Timer]
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/secure-browser-monitor.service" "/etc/systemd/system/secure-browser-monitor.service" "Install secure monitor service"
        safe_mv "/tmp/secure-browser-monitor.timer" "/etc/systemd/system/secure-browser-monitor.timer" "Install secure monitor timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd"
        execute_cmd "systemctl enable secure-browser-monitor.timer" "Enable secure browser monitor timer"
        execute_cmd "systemctl start secure-browser-monitor.timer" "Start secure browser monitor timer"
    fi
    
    end_section_timer "Secure Browser Monitoring"
    log_success "Secure browser automation monitoring created"
    return 0
}

# Test secure Chrome integration
test_secure_chrome_integration() {
    log_section "Testing Secure Chrome Integration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test secure Chrome integration"
        return 0
    fi
    
    start_section_timer "Chrome Integration Test"
    
    # Start Chrome service
    local chrome_dir="$BASE_DIR/services/chrome"
    if [[ -f "$chrome_dir/chrome-service.sh" ]]; then
        log_info "Starting Chrome service for testing"
        bash "$chrome_dir/chrome-service.sh" start
    else
        log_error "Chrome service script not found"
        return 1
    fi
    
    # Wait for Chrome to be ready
    sleep 10
    
    # Test remote debugging endpoint
    log_info "Testing Chrome remote debugging endpoint"
    if curl -s --max-time 10 http://localhost:9222/json/version | jq . >/dev/null 2>&1; then
        log_success "Chrome remote debugging endpoint is accessible and returns valid JSON"
    else
        log_error "Chrome remote debugging endpoint test failed"
        return 1
    fi
    
    # Test creating a new tab
    log_info "Testing Chrome tab creation"
    local tab_response=$(curl -s --max-time 10 -X POST http://localhost:9222/json/new)
    if [[ -n "$tab_response" ]] && echo "$tab_response" | jq .id >/dev/null 2>&1; then
        local tab_id=$(echo "$tab_response" | jq -r .id)
        log_success "Chrome tab creation successful (ID: $tab_id)"
        
        # Clean up test tab
        curl -s --max-time 5 -X POST "http://localhost:9222/json/close/$tab_id" >/dev/null 2>&1
    else
        log_error "Chrome tab creation test failed"
        return 1
    fi
    
    # Test security constraints
    log_info "Verifying security constraints"
    local security_info=$(docker inspect jarvis-chrome --format '{{.HostConfig.SecurityOpt}}' 2>/dev/null)
    if [[ "$security_info" == *"no-new-privileges:true"* ]]; then
        log_success "Security constraints verified"
    else
        log_warning "Security constraints may not be properly applied"
    fi
    
    end_section_timer "Chrome Integration Test"
    log_success "Secure Chrome integration testing completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-setup}" in
        "setup"|"install")
            create_secure_chrome_container && \
            update_n8n_chrome_integration && \
            create_secure_browser_monitoring
            ;;
        "test")
            test_secure_chrome_integration
            ;;
        "chrome-only")
            create_secure_chrome_container
            ;;
        "monitor-only")
            create_secure_browser_monitoring
            ;;
        *)
            echo "Usage: $0 [setup|test|chrome-only|monitor-only]"
            echo ""
            echo "Commands:"
            echo "  setup        - Complete secure browser automation setup (default)"
            echo "  test         - Test secure Chrome integration"
            echo "  chrome-only  - Setup secure Chrome container only"
            echo "  monitor-only - Setup secure browser monitoring only"
            echo ""
            echo "This script implements secure, containerized browser automation"
            echo "without dangerous --no-sandbox flags or host mounting."
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi