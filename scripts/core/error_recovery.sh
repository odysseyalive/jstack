#!/bin/bash
# Error Handling and Recovery System for COMPASS Stack
# Implements comprehensive error recovery, service restoration, and system diagnostics

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🩺 SYSTEM DIAGNOSTICS AND HEALTH ASSESSMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Comprehensive system diagnostics
run_system_diagnostics() {
    log_section "Comprehensive System Diagnostics"
    
    local diagnostics_file="/tmp/jarvis_diagnostics_$(date +%Y%m%d_%H%M%S).log"
    
    {
        echo "COMPASS Stack System Diagnostics Report"
        echo "========================================"
        echo "Timestamp: $(date)"
        echo "Hostname: $(hostname)"
        echo "System: $(uname -a)"
        echo ""
        
        # Docker status
        echo "Docker Status:"
        echo "-------------"
        if command -v docker >/dev/null 2>&1; then
            echo "Docker version: $(docker --version 2>/dev/null || echo 'Not available')"
            echo "Docker status: $(systemctl is-active docker 2>/dev/null || echo 'Unknown')"
            echo "Docker containers:"
            docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Unable to retrieve container information"
            echo ""
            echo "Docker volumes:"
            docker volume ls 2>/dev/null || echo "Unable to retrieve volume information"
            echo ""
            echo "Docker networks:"
            docker network ls 2>/dev/null || echo "Unable to retrieve network information"
        else
            echo "Docker not installed or not accessible"
        fi
        
        echo ""
        echo "System Resources:"
        echo "----------------"
        echo "Memory usage: $(free -h | grep '^Mem:' || echo 'Unable to get memory info')"
        echo "Disk usage: $(df -h / | tail -n 1 || echo 'Unable to get disk info')"
        echo "CPU load: $(uptime || echo 'Unable to get load info')"
        
        echo ""
        echo "COMPASS Stack Services:"
        echo "-----------------------"
        diagnose_service_health
        
        echo ""
        echo "Network Connectivity:"
        echo "--------------------"
        test_network_connectivity
        
        echo ""
        echo "Configuration Status:"
        echo "--------------------"
        diagnose_configuration_status
        
        echo ""
        echo "Log Analysis:"
        echo "------------"
        analyze_recent_logs
        
    } | tee "$diagnostics_file"
    
    log_success "Diagnostics completed. Report saved to: $diagnostics_file"
    return 0
}

# Diagnose individual service health
diagnose_service_health() {
    local services=(
        "supabase-db:5432"
        "supabase-auth:9999"
        "supabase-rest:3000"
        "supabase-studio:3000"
        "n8n:5678"
        "jarvis-chrome:9222"
        "nginx-proxy:80"
    )
    
    for service_info in "${services[@]}"; do
        local service_name="${service_info%:*}"
        local service_port="${service_info#*:}"
        
        echo -n "$service_name: "
        
        # Check if container exists and is running
        if docker ps --filter "name=$service_name" --format '{{.Names}}' | grep -q "$service_name"; then
            # Container is running
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "no-healthcheck")
            
            # Test port connectivity
            local port_status="closed"
            if docker exec "$service_name" netstat -ln 2>/dev/null | grep -q ":$service_port "; then
                port_status="open"
            fi
            
            echo "Running (health: $health_status, port $service_port: $port_status)"
        elif docker ps -a --filter "name=$service_name" --format '{{.Names}}' | grep -q "$service_name"; then
            # Container exists but not running
            local exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$service_name" 2>/dev/null || echo "unknown")
            echo "Stopped (exit code: $exit_code)"
        else
            # Container doesn't exist
            echo "Not found"
        fi
    done
}

# Test network connectivity
test_network_connectivity() {
    local tests=(
        "localhost:80:HTTP"
        "localhost:443:HTTPS"
        "8.8.8.8:53:DNS"
        "github.com:443:External HTTPS"
    )
    
    for test in "${tests[@]}"; do
        IFS=':' read -r host port desc <<< "$test"
        echo -n "$desc ($host:$port): "
        
        if timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            echo "OK"
        else
            echo "Failed"
        fi
    done
}

# Diagnose configuration status
diagnose_configuration_status() {
    echo "Configuration files:"
    
    local config_files=(
        "$PROJECT_ROOT/jstack.config:Main configuration"
        "$BASE_DIR/services/supabase/.env:Supabase environment"
        "$BASE_DIR/services/n8n/.env:N8N environment"
        "$BASE_DIR/services/nginx/conf/nginx.conf:NGINX configuration"
    )
    
    for config_info in "${config_files[@]}"; do
        local file_path="${config_info%:*}"
        local description="${config_info#*:}"
        
        echo -n "  $description: "
        
        if [[ -f "$file_path" ]]; then
            local size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "unknown")
            local modified=$(stat -f%Sm "$file_path" 2>/dev/null || stat -c%y "$file_path" 2>/dev/null || echo "unknown")
            echo "OK (${size} bytes, modified: ${modified})"
        else
            echo "Missing"
        fi
    done
}

# Analyze recent logs for errors
analyze_recent_logs() {
    echo "Recent error analysis (last 100 lines from Docker logs):"
    
    local services=("supabase-db" "supabase-auth" "n8n" "nginx-proxy")
    
    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --format '{{.Names}}' | grep -q "$service"; then
            echo "  $service errors:"
            local error_count=$(docker logs "$service" --tail 100 2>&1 | grep -i -c "error\|fail\|exception\|critical" || echo "0")
            echo "    Error count: $error_count"
            
            if [[ $error_count -gt 0 ]]; then
                echo "    Recent errors:"
                docker logs "$service" --tail 50 2>&1 | grep -i "error\|fail\|exception\|critical" | tail -n 3 | sed 's/^/      /'
            fi
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 SERVICE RECOVERY PROCEDURES
# ═══════════════════════════════════════════════════════════════════════════════

# Attempt to recover a failed service
recover_failed_service() {
    local service_name="$1"
    
    log_section "Attempting to Recover Failed Service: $service_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would attempt to recover service: $service_name"
        return 0
    fi
    
    start_section_timer "Service Recovery"
    
    # Step 1: Gather information about the failure
    log_info "Analyzing service failure"
    local container_status=$(docker inspect --format='{{.State.Status}}' "$service_name" 2>/dev/null || echo "not_found")
    local exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$service_name" 2>/dev/null || echo "unknown")
    local restart_count=$(docker inspect --format='{{.RestartCount}}' "$service_name" 2>/dev/null || echo "unknown")
    
    echo "Service status: $container_status"
    echo "Exit code: $exit_code"
    echo "Restart count: $restart_count"
    
    # Step 2: Collect recent logs
    log_info "Collecting recent logs for analysis"
    local log_file="/tmp/${service_name}_recovery_logs_$(date +%Y%m%d_%H%M%S).log"
    docker logs "$service_name" --tail 100 > "$log_file" 2>&1 || echo "Unable to collect logs" > "$log_file"
    
    # Step 3: Determine recovery strategy based on failure type
    local recovery_strategy=""
    
    if [[ "$container_status" == "not_found" ]]; then
        recovery_strategy="recreate"
    elif [[ "$container_status" == "exited" ]] && [[ "$exit_code" == "0" ]]; then
        recovery_strategy="restart"
    elif [[ "$container_status" == "exited" ]] && [[ "$exit_code" != "0" ]]; then
        recovery_strategy="diagnose_and_restart"
    elif [[ "$container_status" == "running" ]]; then
        recovery_strategy="health_check"
    else
        recovery_strategy="full_recovery"
    fi
    
    log_info "Selected recovery strategy: $recovery_strategy"
    
    # Step 4: Execute recovery strategy
    case "$recovery_strategy" in
        "restart")
            execute_service_restart "$service_name"
            ;;
        "recreate")
            execute_service_recreation "$service_name"
            ;;
        "diagnose_and_restart")
            execute_diagnostic_restart "$service_name" "$log_file"
            ;;
        "health_check")
            execute_health_validation "$service_name"
            ;;
        "full_recovery")
            execute_full_service_recovery "$service_name"
            ;;
    esac
    
    local recovery_result=$?
    
    # Step 5: Verify recovery success
    if [[ $recovery_result -eq 0 ]]; then
        log_info "Verifying service recovery"
        sleep 10
        
        if bash "${PROJECT_ROOT}/scripts/core/service_orchestration.sh" start-service "$service_name"; then
            log_success "Service $service_name recovered successfully"
        else
            log_error "Service recovery verification failed"
            recovery_result=1
        fi
    fi
    
    end_section_timer "Service Recovery"
    return $recovery_result
}

# Execute simple service restart
execute_service_restart() {
    local service_name="$1"
    
    log_info "Executing simple restart for $service_name"
    
    if docker restart "$service_name" >/dev/null 2>&1; then
        log_success "Service restart completed"
        return 0
    else
        log_error "Service restart failed"
        return 1
    fi
}

# Execute service recreation
execute_service_recreation() {
    local service_name="$1"
    
    log_info "Recreating service: $service_name"
    
    # Determine service directory and recreate
    local service_dir=""
    case "$service_name" in
        supabase-*)
            service_dir="$BASE_DIR/services/supabase"
            ;;
        "n8n")
            service_dir="$BASE_DIR/services/n8n"
            ;;
        "jarvis-chrome")
            service_dir="$BASE_DIR/services/chrome"
            ;;
        "nginx-proxy")
            service_dir="$BASE_DIR/services/nginx"
            ;;
    esac
    
    if [[ -n "$service_dir" ]] && [[ -d "$service_dir" ]]; then
        if docker_cmd "cd $service_dir && docker-compose up -d $service_name" "Recreate $service_name"; then
            return 0
        else
            return 1
        fi
    else
        log_error "Unable to determine service directory for $service_name"
        return 1
    fi
}

# Execute diagnostic restart with log analysis
execute_diagnostic_restart() {
    local service_name="$1"
    local log_file="$2"
    
    log_info "Performing diagnostic restart for $service_name"
    
    # Analyze logs for common issues
    if grep -q -i "out of memory\|oom" "$log_file"; then
        log_warning "Detected out of memory condition - may need resource adjustment"
    fi
    
    if grep -q -i "permission denied\|access denied" "$log_file"; then
        log_warning "Detected permission issues - checking file permissions"
        # Could add permission fixing logic here
    fi
    
    if grep -q -i "connection refused\|network\|timeout" "$log_file"; then
        log_warning "Detected network connectivity issues"
    fi
    
    # Attempt restart with fresh configuration
    execute_service_restart "$service_name"
}

# Execute health validation for running service
execute_health_validation() {
    local service_name="$1"
    
    log_info "Validating health of running service: $service_name"
    
    # Use the enhanced health check from service orchestration
    if bash "${PROJECT_ROOT}/scripts/core/service_orchestration.sh" start-service "$service_name"; then
        log_success "Service health validation passed"
        return 0
    else
        log_warning "Service health validation failed - attempting restart"
        execute_service_restart "$service_name"
    fi
}

# Execute full service recovery (nuclear option)
execute_full_service_recovery() {
    local service_name="$1"
    
    log_info "Executing full service recovery for $service_name"
    
    # Stop service
    docker stop "$service_name" >/dev/null 2>&1 || true
    
    # Remove service
    docker rm "$service_name" >/dev/null 2>&1 || true
    
    # Remove related volumes if safe
    case "$service_name" in
        "jarvis-chrome")
            docker volume rm chrome_data >/dev/null 2>&1 || true
            ;;
        "nginx-proxy")
            # Don't remove SSL certificates
            ;;
        # Be cautious with database volumes
    esac
    
    # Recreate service
    execute_service_recreation "$service_name"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚨 AUTOMATED RECOVERY SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

# Monitor and auto-recover failed services
auto_recovery_monitor() {
    log_section "Automated Service Recovery Monitor"
    
    local recovery_attempts=0
    local max_recovery_attempts=3
    local services_to_monitor=(
        "supabase-db"
        "supabase-auth"
        "n8n"
        "nginx-proxy"
    )
    
    while [[ $recovery_attempts -lt $max_recovery_attempts ]]; do
        local failed_services=()
        
        # Check each critical service
        for service in "${services_to_monitor[@]}"; do
            if ! is_service_healthy "$service"; then
                failed_services+=("$service")
            fi
        done
        
        # If no failures, we're done
        if [[ ${#failed_services[@]} -eq 0 ]]; then
            log_success "All monitored services are healthy"
            return 0
        fi
        
        # Attempt recovery for failed services
        log_warning "Detected ${#failed_services[@]} failed services: ${failed_services[*]}"
        
        local recovery_success=true
        for failed_service in "${failed_services[@]}"; do
            log_info "Attempting recovery for $failed_service (attempt $((recovery_attempts + 1))/$max_recovery_attempts)"
            
            if ! recover_failed_service "$failed_service"; then
                log_error "Recovery failed for $failed_service"
                recovery_success=false
            fi
        done
        
        # If all recoveries succeeded, check again
        if [[ "$recovery_success" == "true" ]]; then
            log_info "Recovery attempt completed - verifying system health"
            sleep 30  # Wait for services to stabilize
        else
            recovery_attempts=$((recovery_attempts + 1))
            if [[ $recovery_attempts -lt $max_recovery_attempts ]]; then
                log_warning "Some recoveries failed - waiting before next attempt"
                sleep 60
            fi
        fi
    done
    
    log_error "Auto-recovery failed after $max_recovery_attempts attempts"
    return 1
}

# Check if a service is healthy
is_service_healthy() {
    local service_name="$1"
    
    # Check if container is running
    if ! docker ps --filter "name=$service_name" --format '{{.Names}}' | grep -q "$service_name"; then
        return 1
    fi
    
    # Check Docker health status if available
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "unknown")
    if [[ "$health_status" == "unhealthy" ]]; then
        return 1
    fi
    
    # Service-specific health checks
    case "$service_name" in
        "supabase-db")
            docker exec "$service_name" pg_isready -U postgres >/dev/null 2>&1
            ;;
        "supabase-auth"|"supabase-rest")
            docker exec "$service_name" wget --spider -q "http://localhost:9999/health" >/dev/null 2>&1 || \
            docker exec "$service_name" curl -s -f "http://localhost:9999/health" >/dev/null 2>&1
            ;;
        "n8n")
            docker exec "$service_name" wget --spider -q "http://localhost:5678/healthz" >/dev/null 2>&1 || \
            docker exec "$service_name" curl -s -f "http://localhost:5678/healthz" >/dev/null 2>&1
            ;;
        "nginx-proxy")
            docker exec "$service_name" nginx -t >/dev/null 2>&1
            ;;
        *)
            # Default: just check if container is running
            return 0
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📋 SYSTEM RECOVERY PROCEDURES
# ═══════════════════════════════════════════════════════════════════════════════

# Complete system recovery from backup
system_recovery_from_backup() {
    local backup_file="$1"
    
    log_section "Complete System Recovery from Backup"
    
    if [[ -z "$backup_file" ]]; then
        log_error "No backup file specified for system recovery"
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_warning "This will completely restore the system from backup"
    log_warning "All current data will be replaced with backup data"
    
    # Stop all services
    log_info "Stopping all services for recovery"
    bash "${PROJECT_ROOT}/scripts/core/service_orchestration.sh" stop-all
    
    # Perform backup restore
    log_info "Restoring system from backup"
    if bash "${PROJECT_ROOT}/scripts/core/backup.sh" restore "$backup_file"; then
        log_success "System restore from backup completed"
        
        # Start services
        log_info "Starting services after recovery"
        if bash "${PROJECT_ROOT}/scripts/core/service_orchestration.sh" start-all; then
            log_success "System recovery completed successfully"
            return 0
        else
            log_error "Service startup failed after recovery"
            return 1
        fi
    else
        log_error "System restore from backup failed"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-diagnostics}" in
        "diagnostics"|"diagnose")
            run_system_diagnostics
            ;;
        "recover")
            if [[ -n "$2" ]]; then
                recover_failed_service "$2"
            else
                echo "Error: recover requires service name"
                echo "Usage: $0 recover [service_name]"
                exit 1
            fi
            ;;
        "auto-recovery"|"monitor")
            auto_recovery_monitor
            ;;
        "system-recovery")
            if [[ -n "$2" ]]; then
                system_recovery_from_backup "$2"
            else
                echo "Error: system-recovery requires backup file"
                echo "Usage: $0 system-recovery [backup_file]"
                exit 1
            fi
            ;;
        *)
            echo "COMPASS Stack Error Handling and Recovery System"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  diagnostics           - Run comprehensive system diagnostics (default)"
            echo "  recover SERVICE       - Attempt to recover a failed service"
            echo "  auto-recovery         - Monitor and auto-recover failed services"
            echo "  system-recovery FILE  - Complete system recovery from backup"
            echo ""
            echo "Available Services for Recovery:"
            echo "  supabase-db, supabase-auth, supabase-rest, supabase-studio"
            echo "  n8n, jarvis-chrome, nginx-proxy"
            echo ""
            echo "Examples:"
            echo "  $0 diagnostics                          # Run system diagnostics"
            echo "  $0 recover n8n                          # Recover failed N8N service"
            echo "  $0 auto-recovery                        # Start automated recovery monitor"
            echo "  $0 system-recovery backup_file.tar.gz   # Complete system recovery"
            echo ""
            echo "This script provides comprehensive error handling and recovery capabilities"
            echo "for the COMPASS Stack infrastructure."
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi