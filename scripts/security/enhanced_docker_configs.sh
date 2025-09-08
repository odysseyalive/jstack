#!/bin/bash
# Enhanced Docker Security Configurations for JStack Stack
# Implements capability management, security constraints, and hardened container settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔒 ENHANCED CONTAINER SECURITY CONFIGURATIONS
# ═══════════════════════════════════════════════════════════════════════════════

create_enhanced_n8n_config() {
    log_section "Creating Enhanced N8N Container Security Configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create enhanced N8N security configuration"
        return 0
    fi
    
    start_section_timer "N8N Security Config"
    
    local config_dir="$BASE_DIR/security/docker-configs"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $config_dir" "Create Docker configs directory"
    
    # Enhanced N8N Docker Compose with security hardening
    cat > /tmp/n8n-secure.yml << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    
    # Security Hardening
    user: "1000:1000"  # Non-root user
    read_only: true     # Read-only root filesystem
    
    # Capability Management - Drop all, add only essential
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - DAC_OVERRIDE
      - SETGID
      - SETUID
    
    # Security Options
    security_opt:
      - no-new-privileges:true
      - apparmor:docker-n8n-enhanced
      - seccomp:/home/jarvis/jstack/security/configs/default-seccomp.json
    
    # Resource Limits
    mem_limit: ${N8N_MEMORY_LIMIT}
    cpus: ${N8N_CPU_LIMIT}
    mem_reservation: 512m
    
    # Environment Variables
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - EXECUTIONS_PROCESS=main
      - EXECUTIONS_TIMEOUT=${N8N_EXECUTION_TIMEOUT}
      - EXECUTIONS_DATA_MAX_AGE=${N8N_MAX_EXECUTION_HISTORY}
      - N8N_METRICS=true
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      
      # Security Environment
      - N8N_SECURE_COOKIE=true
      - N8N_DISABLE_UI=false
      
    # Volumes (with security constraints)
    volumes:
      - n8n_data:/home/node/.n8n:rw,nodev,nosuid
      - /tmp/n8n:/tmp:rw,nodev,nosuid,noexec,size=1g
    
    # Tmpfs mounts for sensitive temporary data
    tmpfs:
      - /run:rw,noexec,nosuid,size=100m
      - /var/tmp:rw,noexec,nosuid,size=100m
    
    # Network Configuration
    networks:
      - ${PRIVATE_TIER}
    
    # Health Check
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    # Logging Configuration
    logging:
      driver: "json-file"
      options:
        max-size: "${CONTAINER_LOG_MAX_SIZE}"
        max-file: "${CONTAINER_LOG_MAX_FILES}"
        tag: "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"

volumes:
  n8n_data:
    driver: local
    driver_opts:
      type: none
      o: bind,nodev,nosuid
      device: /home/jarvis/jstack/data/n8n

networks:
  ${PRIVATE_TIER}:
    external: true
    name: ${PRIVATE_TIER}
EOF
    
    safe_mv "/tmp/n8n-secure.yml" "$config_dir/n8n-secure.yml" "Install enhanced N8N config"
    
    end_section_timer "N8N Security Config"
}

create_enhanced_postgres_config() {
    log_section "Creating Enhanced PostgreSQL Container Security Configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create enhanced PostgreSQL security configuration"
        return 0
    fi
    
    start_section_timer "PostgreSQL Security Config"
    
    local config_dir="$BASE_DIR/security/docker-configs"
    
    # Enhanced PostgreSQL Docker Compose with security hardening
    cat > /tmp/postgres-secure.yml << EOF
version: '3.8'

services:
  postgres:
    image: supabase/postgres:15.1.0.104
    container_name: supabase-db
    restart: unless-stopped
    
    # Security Hardening
    user: "999:999"     # postgres user
    read_only: false    # Database needs write access to data directory
    
    # Capability Management
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - SETGID
      - SETUID
      - IPC_LOCK         # For shared memory
    
    # Security Options
    security_opt:
      - no-new-privileges:true
      - apparmor:docker-postgres-enhanced
      - seccomp:/home/jarvis/jstack/security/configs/default-seccomp.json
    
    # Resource Limits
    mem_limit: ${POSTGRES_MEMORY_LIMIT}
    cpus: ${POSTGRES_CPU_LIMIT}
    mem_reservation: 1g
    
    # Shared Memory for PostgreSQL
    shm_size: 256m
    
    # Environment Variables
    environment:
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=${SUPABASE_DB_NAME}
      - POSTGRES_USER=postgres
      
      # PostgreSQL Performance Tuning
      - POSTGRES_SHARED_BUFFERS=${POSTGRES_SHARED_BUFFERS}
      - POSTGRES_EFFECTIVE_CACHE_SIZE=${POSTGRES_EFFECTIVE_CACHE_SIZE}
      - POSTGRES_WORK_MEM=${POSTGRES_WORK_MEM}
      - POSTGRES_MAINTENANCE_WORK_MEM=${POSTGRES_MAINTENANCE_WORK_MEM}
      - POSTGRES_MAX_CONNECTIONS=${POSTGRES_MAX_CONNECTIONS}
      
      # Security Settings
      - POSTGRES_LOG_CONNECTIONS=on
      - POSTGRES_LOG_DISCONNECTIONS=on
      - POSTGRES_LOG_STATEMENT=all
      - POSTGRES_LOG_MIN_DURATION_STATEMENT=1000
    
    # Volumes (with security constraints)
    volumes:
      - postgres_data:/var/lib/postgresql/data:rw,nodev,nosuid
      - /tmp/postgres:/tmp:rw,nodev,nosuid,noexec,size=1g
    
    # Tmpfs mounts
    tmpfs:
      - /run/postgresql:rw,noexec,nosuid,size=100m
    
    # Network Configuration
    networks:
      - ${PRIVATE_TIER}
    
    # Health Check
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d ${SUPABASE_DB_NAME}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    # Logging Configuration
    logging:
      driver: "json-file"
      options:
        max-size: "${CONTAINER_LOG_MAX_SIZE}"
        max-file: "${CONTAINER_LOG_MAX_FILES}"
        tag: "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"

volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      o: bind,nodev,nosuid
      device: /home/jarvis/jstack/data/postgres

networks:
  ${PRIVATE_TIER}:
    external: true
    name: ${PRIVATE_TIER}
EOF
    
    safe_mv "/tmp/postgres-secure.yml" "$config_dir/postgres-secure.yml" "Install enhanced PostgreSQL config"
    
    end_section_timer "PostgreSQL Security Config"
}

create_enhanced_nginx_config() {
    log_section "Creating Enhanced NGINX Container Security Configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create enhanced NGINX security configuration"
        return 0
    fi
    
    start_section_timer "NGINX Security Config"
    
    local config_dir="$BASE_DIR/security/docker-configs"
    
    # Enhanced NGINX Docker Compose with security hardening
    cat > /tmp/nginx-secure.yml << EOF
version: '3.8'

services:
  nginx:
    image: nginx:stable-alpine
    container_name: nginx-proxy
    restart: unless-stopped
    
    # Security Hardening
    user: "101:101"     # nginx user
    read_only: true     # Read-only root filesystem
    
    # Capability Management
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - DAC_OVERRIDE
      - SETGID
      - SETUID
    
    # Security Options
    security_opt:
      - no-new-privileges:true
      - apparmor:unconfined  # Use default for nginx
      - seccomp:/home/jarvis/jstack/security/configs/default-seccomp.json
    
    # Resource Limits
    mem_limit: ${NGINX_MEMORY_LIMIT}
    cpus: ${NGINX_CPU_LIMIT}
    mem_reservation: 64m
    
    # Ports
    ports:
      - "80:80"
      - "443:443"
    
    # Volumes (with security constraints)
    volumes:
      - /home/jarvis/jstack/services/nginx/conf/nginx.conf:/etc/nginx/nginx.conf:ro
      - /home/jarvis/jstack/services/nginx/conf:/etc/nginx/conf.d:ro
      - /home/jarvis/jstack/services/nginx/ssl:/etc/letsencrypt:ro
      - nginx_logs:/var/log/nginx:rw,nodev,nosuid
      - nginx_cache:/var/cache/nginx:rw,nodev,nosuid,noexec
    
    # Tmpfs mounts for temporary files
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=100m
      - /var/run:rw,noexec,nosuid,size=50m
    
    # Network Configuration
    networks:
      - ${PUBLIC_TIER}
      - ${PRIVATE_TIER}
    
    # Health Check
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    
    # Logging Configuration
    logging:
      driver: "json-file"
      options:
        max-size: "${CONTAINER_LOG_MAX_SIZE}"
        max-file: "${CONTAINER_LOG_MAX_FILES}"
        tag: "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
    
    # Dependencies
    depends_on:
      - n8n
      - supabase-db

volumes:
  nginx_logs:
    driver: local
    driver_opts:
      type: none
      o: bind,nodev,nosuid
      device: /home/jarvis/jstack/logs/nginx
  
  nginx_cache:
    driver: local

networks:
  ${PUBLIC_TIER}:
    external: true
    name: ${PUBLIC_TIER}
  ${PRIVATE_TIER}:
    external: true
    name: ${PRIVATE_TIER}
EOF
    
    safe_mv "/tmp/nginx-secure.yml" "$config_dir/nginx-secure.yml" "Install enhanced NGINX config"
    
    end_section_timer "NGINX Security Config"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🛠️ CONTAINER SECURITY VALIDATION TOOLS
# ═══════════════════════════════════════════════════════════════════════════════

create_security_validation_script() {
    log_section "Creating Container Security Validation Scripts"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create security validation scripts"
        return 0
    fi
    
    start_section_timer "Validation Scripts"
    
    local config_dir="$BASE_DIR/security/docker-configs"
    
    # Container Security Validation Script
    cat > /tmp/validate-container-security.sh << 'EOF'
#!/bin/bash
# Container Security Validation for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

validate_container_security() {
    log_section "Validating Container Security Configuration"
    
    local containers=("n8n" "supabase-db" "nginx-proxy")
    local failed_checks=0
    
    for container in "${containers[@]}"; do
        log_info "Validating security for container: $container"
        
        if ! docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            log_warning "Container $container is not running"
            continue
        fi
        
        echo "=== Security Validation: $container ==="
        
        # Check if running as non-root
        local user_id=$(docker exec "$container" id -u 2>/dev/null || echo "unknown")
        if [[ "$user_id" == "0" ]]; then
            echo "❌ FAIL: Container running as root (UID: $user_id)"
            ((failed_checks++))
        else
            echo "✅ PASS: Container running as non-root (UID: $user_id)"
        fi
        
        # Check read-only root filesystem
        local readonly_root=$(docker inspect "$container" --format='{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null)
        if [[ "$readonly_root" == "true" ]]; then
            echo "✅ PASS: Read-only root filesystem enabled"
        else
            echo "⚠️  WARN: Read-only root filesystem not enabled"
        fi
        
        # Check no-new-privileges
        local no_new_privs=$(docker inspect "$container" --format='{{.HostConfig.SecurityOpt}}' 2>/dev/null | grep -o "no-new-privileges:true" || echo "")
        if [[ -n "$no_new_privs" ]]; then
            echo "✅ PASS: No-new-privileges enabled"
        else
            echo "❌ FAIL: No-new-privileges not enabled"
            ((failed_checks++))
        fi
        
        # Check capabilities
        local cap_drop=$(docker inspect "$container" --format='{{.HostConfig.CapDrop}}' 2>/dev/null)
        if [[ "$cap_drop" == *"ALL"* ]]; then
            echo "✅ PASS: All capabilities dropped"
        else
            echo "❌ FAIL: Capabilities not properly dropped"
            ((failed_checks++))
        fi
        
        # Check AppArmor profile
        local apparmor_profile=$(docker inspect "$container" --format='{{.AppArmorProfile}}' 2>/dev/null)
        if [[ -n "$apparmor_profile" && "$apparmor_profile" != "unconfined" ]]; then
            echo "✅ PASS: AppArmor profile applied: $apparmor_profile"
        else
            echo "⚠️  WARN: No AppArmor profile or unconfined"
        fi
        
        # Check resource limits
        local memory_limit=$(docker inspect "$container" --format='{{.HostConfig.Memory}}' 2>/dev/null)
        if [[ "$memory_limit" != "0" ]]; then
            echo "✅ PASS: Memory limit set: $(numfmt --to=iec $memory_limit)"
        else
            echo "❌ FAIL: No memory limit set"
            ((failed_checks++))
        fi
        
        # Check network configuration
        local networks=$(docker inspect "$container" --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
        if [[ "$networks" =~ (${PRIVATE_TIER}|${PUBLIC_TIER}) ]]; then
            echo "✅ PASS: Using custom networks: $networks"
        else
            echo "⚠️  WARN: Not using expected custom networks"
        fi
        
        echo ""
    done
    
    # Summary
    if [[ $failed_checks -eq 0 ]]; then
        log_success "All critical security checks passed!"
        return 0
    else
        log_warning "Security validation completed with $failed_checks failed checks"
        return 1
    fi
}

run_cis_benchmark_check() {
    log_section "Running CIS Docker Benchmark Checks"
    
    local benchmark_script="/home/jarvis/jstack/security/docker-bench/docker-bench-security.sh"
    
    if [[ -f "$benchmark_script" ]]; then
        log_info "Running Docker Bench Security..."
        "$benchmark_script" | grep -E "(WARN|FAIL|PASS)" | head -20
    else
        log_warning "Docker Bench Security not found. Install with: bash scripts/security/container_security.sh bench"
    fi
}

case "${1:-validate}" in
    "security") validate_container_security ;;
    "cis") run_cis_benchmark_check ;;
    "all") validate_container_security; run_cis_benchmark_check ;;
    *) echo "Usage: $0 [security|cis|all]"
       echo "Container security validation for JStack Stack" ;;
esac
EOF
    
    safe_mv "/tmp/validate-container-security.sh" "$config_dir/validate-container-security.sh" "Install security validation script"
    execute_cmd "chmod +x $config_dir/validate-container-security.sh" "Make validation script executable"
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$config_dir/" "Set security configs ownership"
    
    end_section_timer "Validation Scripts"
}

# Main function
main() {
    case "${1:-setup}" in
        "n8n") create_enhanced_n8n_config ;;
        "postgres") create_enhanced_postgres_config ;;
        "nginx") create_enhanced_nginx_config ;;
        "validate") create_security_validation_script ;;
        "setup"|"all") 
            create_enhanced_n8n_config
            create_enhanced_postgres_config
            create_enhanced_nginx_config
            create_security_validation_script
            ;;
        *) echo "Usage: $0 [setup|n8n|postgres|nginx|validate|all]"
           echo "Enhanced Docker security configurations for JStack Stack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi