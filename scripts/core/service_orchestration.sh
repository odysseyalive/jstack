#!/bin/bash
# Service Orchestration and Dependency Management for COMPASS Stack
# Handles proper service startup coordination, health checks, and dependency management

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔗 SERVICE DEPENDENCY MAPPING
# ═══════════════════════════════════════════════════════════════════════════════

# Define service dependency graph
declare -A SERVICE_DEPENDENCIES
SERVICE_DEPENDENCIES["supabase-db"]=""                    # No dependencies - foundation service
SERVICE_DEPENDENCIES["supabase-auth"]="supabase-db"       # Depends on database
SERVICE_DEPENDENCIES["supabase-rest"]="supabase-db"       # Depends on database
SERVICE_DEPENDENCIES["supabase-realtime"]="supabase-db"   # Depends on database
SERVICE_DEPENDENCIES["supabase-meta"]="supabase-db"       # Depends on database
SERVICE_DEPENDENCIES["supabase-storage"]="supabase-db supabase-rest"  # Depends on database and REST API
SERVICE_DEPENDENCIES["supabase-imgproxy"]="supabase-storage"  # Depends on storage
SERVICE_DEPENDENCIES["supabase-studio"]="supabase-meta supabase-auth supabase-rest"  # Depends on multiple services
SERVICE_DEPENDENCIES["supabase-kong"]="supabase-auth supabase-rest supabase-realtime supabase-storage"  # API Gateway depends on all APIs
SERVICE_DEPENDENCIES["n8n"]="supabase-db"                 # N8N uses database for storage
SERVICE_DEPENDENCIES["jarvis-chrome"]=""                  # Standalone service for browser automation
SERVICE_DEPENDENCIES["nginx-proxy"]="supabase-kong supabase-studio n8n"  # Reverse proxy depends on all web services

# Define service startup timeout and health check parameters
declare -A SERVICE_TIMEOUTS
SERVICE_TIMEOUTS["supabase-db"]="120"
SERVICE_TIMEOUTS["supabase-auth"]="60"
SERVICE_TIMEOUTS["supabase-rest"]="60"
SERVICE_TIMEOUTS["supabase-realtime"]="60"
SERVICE_TIMEOUTS["supabase-meta"]="60"
SERVICE_TIMEOUTS["supabase-storage"]="60"
SERVICE_TIMEOUTS["supabase-imgproxy"]="60"
SERVICE_TIMEOUTS["supabase-studio"]="90"
SERVICE_TIMEOUTS["supabase-kong"]="90"
SERVICE_TIMEOUTS["n8n"]="120"
SERVICE_TIMEOUTS["jarvis-chrome"]="60"
SERVICE_TIMEOUTS["nginx-proxy"]="60"

# ═══════════════════════════════════════════════════════════════════════════════
# 🩺 ENHANCED HEALTH CHECKING
# ═══════════════════════════════════════════════════════════════════════════════

# Enhanced health check with multiple validation layers
enhanced_health_check() {
    local service_name="$1"
    local timeout="${2:-60}"
    local interval="${3:-5}"
    
    log_info "Enhanced health check for $service_name (timeout: ${timeout}s)"
    
    local elapsed=0
    local health_status="starting"
    
    while [ $elapsed -lt $timeout ]; do
        # Layer 1: Container running check
        if ! docker ps --filter "name=$service_name" --format '{{.Names}}' | grep -q "$service_name"; then
            log_error "$service_name container is not running"
            return 1
        fi
        
        # Layer 2: Docker health check
        local docker_health=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "none")
        
        # Layer 3: Service-specific health validation
        local service_health="unknown"
        case "$service_name" in
            "supabase-db")
                if docker exec "$service_name" pg_isready -U postgres >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
            "supabase-auth"|"supabase-rest"|"supabase-realtime"|"supabase-meta"|"supabase-storage")
                local port=$(get_service_port "$service_name")
                if [[ -n "$port" ]] && docker exec "$service_name" wget --spider -q "http://localhost:$port/health" >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
            "supabase-studio")
                if docker exec "$service_name" wget --spider -q "http://localhost:3000/api/health" >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
            "supabase-kong")
                if docker exec "$service_name" wget --spider -q "http://localhost:8001/status" >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
            "n8n")
                if docker exec "$service_name" wget --spider -q "http://localhost:5678/healthz" >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
            "jarvis-chrome")
                if curl -s --max-time 3 "http://localhost:9222/json/version" >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
            "nginx-proxy")
                if docker exec "$service_name" nginx -t >/dev/null 2>&1; then
                    service_health="healthy"
                fi
                ;;
        esac
        
        # Evaluate overall health
        if [[ "$docker_health" == "healthy" ]] || [[ "$service_health" == "healthy" ]]; then
            log_success "$service_name is healthy (docker: $docker_health, service: $service_health)"
            return 0
        elif [[ "$docker_health" == "unhealthy" ]]; then
            log_error "$service_name Docker health check failed"
            return 1
        fi
        
        # Show progress
        if [[ $((elapsed % 15)) -eq 0 ]]; then
            log_info "$service_name health status: docker=$docker_health, service=$service_health (${elapsed}s elapsed)"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "$service_name failed to become healthy within ${timeout}s"
    return 1
}

# Get service port for health checking
get_service_port() {
    local service_name="$1"
    case "$service_name" in
        "supabase-auth"|"supabase-rest"|"supabase-realtime"|"supabase-storage") echo "9999" ;;
        "supabase-meta") echo "8080" ;;
        "supabase-studio") echo "3000" ;;
        "supabase-kong") echo "8001" ;;
        "n8n") echo "5678" ;;
        "jarvis-chrome") echo "9222" ;;
        "nginx-proxy") echo "80" ;;
        *) echo "" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 COORDINATED SERVICE STARTUP
# ═══════════════════════════════════════════════════════════════════════════════

# Start service with dependency resolution
start_service_with_dependencies() {
    local service_name="$1"
    local started_services=()
    
    log_section "Starting Service with Dependencies: $service_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start $service_name and its dependencies"
        return 0
    fi
    
    # Get dependency order
    local startup_order=($(get_startup_order "$service_name"))
    
    log_info "Service startup order: ${startup_order[*]}"
    
    # Start services in dependency order
    for current_service in "${startup_order[@]}"; do
        if is_service_running "$current_service"; then
            log_info "$current_service is already running - skipping"
            continue
        fi
        
        log_info "Starting service: $current_service"
        
        # Start the service
        if start_individual_service "$current_service"; then
            started_services+=("$current_service")
            
            # Wait for service to be healthy
            local timeout="${SERVICE_TIMEOUTS[$current_service]:-60}"
            if enhanced_health_check "$current_service" "$timeout"; then
                log_success "$current_service started and is healthy"
            else
                log_error "$current_service failed health check"
                
                # Rollback started services
                rollback_started_services "${started_services[@]}"
                return 1
            fi
        else
            log_error "Failed to start $current_service"
            
            # Rollback started services
            rollback_started_services "${started_services[@]}"
            return 1
        fi
        
        # Brief pause between service starts
        sleep 2
    done
    
    log_success "All services started successfully for: $service_name"
    return 0
}

# Calculate startup order based on dependencies
get_startup_order() {
    local target_service="$1"
    local visited=()
    local result=()
    
    # Depth-first search to resolve dependencies
    resolve_dependencies "$target_service" visited result
    
    # Remove duplicates while preserving order
    local ordered_services=()
    for service in "${result[@]}"; do
        if [[ ! " ${ordered_services[*]} " =~ " ${service} " ]]; then
            ordered_services+=("$service")
        fi
    done
    
    printf '%s\n' "${ordered_services[@]}"
}

# Recursive dependency resolution
resolve_dependencies() {
    local service="$1"
    local -n visited_ref=$2
    local -n result_ref=$3
    
    # Skip if already visited
    if [[ " ${visited_ref[*]} " =~ " ${service} " ]]; then
        return
    fi
    
    visited_ref+=("$service")
    
    # Get dependencies for this service
    local deps="${SERVICE_DEPENDENCIES[$service]}"
    
    # Recursively resolve dependencies first
    if [[ -n "$deps" ]]; then
        for dep in $deps; do
            resolve_dependencies "$dep" visited_ref result_ref
        done
    fi
    
    # Add this service to result
    result_ref+=("$service")
}

# Check if service is running
is_service_running() {
    local service_name="$1"
    docker ps --filter "name=$service_name" --format '{{.Names}}' | grep -q "$service_name"
}

# Start individual service
start_individual_service() {
    local service_name="$1"
    
    log_info "Starting individual service: $service_name"
    
    # Determine service directory and start command
    local service_dir=""
    local start_command=""
    
    case "$service_name" in
        supabase-*)
            service_dir="$BASE_DIR/services/supabase"
            start_command="docker-compose up -d $service_name"
            ;;
        "n8n")
            service_dir="$BASE_DIR/services/n8n"
            start_command="docker-compose up -d"
            ;;
        "jarvis-chrome")
            service_dir="$BASE_DIR/services/chrome"
            start_command="docker-compose up -d"
            ;;
        "nginx-proxy")
            service_dir="$BASE_DIR/services/nginx"
            start_command="docker-compose up -d"
            ;;
        *)
            log_error "Unknown service: $service_name"
            return 1
            ;;
    esac
    
    if [[ -d "$service_dir" ]]; then
        if docker_cmd "cd $service_dir && $start_command" "Start $service_name"; then
            return 0
        else
            log_error "Failed to start $service_name"
            return 1
        fi
    else
        log_error "Service directory not found: $service_dir"
        return 1
    fi
}

# Rollback started services in reverse order
rollback_started_services() {
    local services=("$@")
    
    if [[ ${#services[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_warning "Rolling back started services due to failure"
    
    # Reverse the array
    local reversed_services=()
    for ((i=${#services[@]}-1; i>=0; i--)); do
        reversed_services+=("${services[i]}")
    done
    
    # Stop services in reverse order
    for service in "${reversed_services[@]}"; do
        log_info "Stopping $service for rollback"
        stop_individual_service "$service" || true
    done
}

# Stop individual service
stop_individual_service() {
    local service_name="$1"
    
    log_info "Stopping service: $service_name"
    
    # Determine service directory
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
    
    if [[ -d "$service_dir" ]]; then
        docker_cmd "cd $service_dir && docker-compose stop $service_name" "Stop $service_name" || true
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 COMPLETE SYSTEM ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Start all services in proper order
start_all_services() {
    log_section "Starting All Services with Dependency Management"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start all services in dependency order"
        return 0
    fi
    
    # Define complete service startup order
    local all_services=(
        "supabase-db"
        "supabase-auth"
        "supabase-rest"
        "supabase-realtime"
        "supabase-meta"
        "supabase-storage"
        "supabase-imgproxy"
        "supabase-studio"
        "supabase-kong"
        "n8n"
    )
    
    # Add Chrome if browser automation is enabled
    if [[ "$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        all_services+=("jarvis-chrome")
    fi
    
    # Add NGINX last (depends on all web services)
    all_services+=("nginx-proxy")
    
    # Start each service with dependency checking
    for service in "${all_services[@]}"; do
        if is_service_running "$service"; then
            log_info "$service is already running"
            
            # Quick health check
            if enhanced_health_check "$service" 30; then
                log_success "$service is running and healthy"
            else
                log_warning "$service is running but may not be healthy"
            fi
        else
            log_info "Starting $service with dependencies"
            if ! start_service_with_dependencies "$service"; then
                log_error "Failed to start $service - aborting startup sequence"
                return 1
            fi
        fi
    done
    
    log_success "All services started successfully"
    
    # Final system health check
    system_health_check
    
    return 0
}

# Stop all services in reverse dependency order
stop_all_services() {
    log_section "Stopping All Services"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would stop all services"
        return 0
    fi
    
    # Stop in reverse order
    local all_services=(
        "nginx-proxy"
        "jarvis-chrome"
        "n8n"
        "supabase-kong"
        "supabase-studio"
        "supabase-imgproxy"
        "supabase-storage"
        "supabase-meta"
        "supabase-realtime"
        "supabase-rest"
        "supabase-auth"
        "supabase-db"
    )
    
    for service in "${all_services[@]}"; do
        if is_service_running "$service"; then
            log_info "Stopping $service"
            stop_individual_service "$service"
        fi
    done
    
    log_success "All services stopped"
}

# System-wide health check
system_health_check() {
    log_section "System Health Check"
    
    local healthy_services=0
    local total_services=0
    
    local all_services=($(docker ps --filter "label=com.docker.compose.project" --format '{{.Names}}' | grep -E "(supabase|n8n|jarvis|nginx)" | sort))
    
    if [[ ${#all_services[@]} -eq 0 ]]; then
        log_warning "No COMPASS Stack services found running"
        return 1
    fi
    
    echo "Service Health Status:"
    echo "====================="
    
    for service in "${all_services[@]}"; do
        total_services=$((total_services + 1))
        
        if enhanced_health_check "$service" 15 2; then
            echo "✓ $service: Healthy"
            healthy_services=$((healthy_services + 1))
        else
            echo "✗ $service: Unhealthy or unreachable"
        fi
    done
    
    echo ""
    echo "Summary: $healthy_services/$total_services services healthy"
    
    if [[ $healthy_services -eq $total_services ]]; then
        log_success "System health check passed - all services healthy"
        return 0
    else
        log_warning "System health check completed with warnings - some services unhealthy"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-start-all}" in
        "start-all"|"start")
            start_all_services
            ;;
        "stop-all"|"stop")
            stop_all_services
            ;;
        "start-service")
            if [[ -n "$2" ]]; then
                start_service_with_dependencies "$2"
            else
                echo "Error: start-service requires service name"
                exit 1
            fi
            ;;
        "health"|"health-check")
            system_health_check
            ;;
        "status")
            system_health_check
            ;;
        *)
            echo "COMPASS Stack Service Orchestration"
            echo ""
            echo "Usage: $0 [COMMAND] [SERVICE_NAME]"
            echo ""
            echo "Commands:"
            echo "  start-all           - Start all services in proper dependency order (default)"
            echo "  stop-all           - Stop all services in reverse dependency order"
            echo "  start-service NAME - Start specific service with its dependencies"
            echo "  health             - Run system health check"
            echo "  status             - Show service status (same as health)"
            echo ""
            echo "Available Services:"
            echo "  supabase-db, supabase-auth, supabase-rest, supabase-realtime"
            echo "  supabase-meta, supabase-storage, supabase-studio, supabase-kong"
            echo "  n8n, jarvis-chrome, nginx-proxy"
            echo ""
            echo "Examples:"
            echo "  $0 start-all                    # Start all services"
            echo "  $0 start-service nginx-proxy    # Start NGINX and its dependencies"
            echo "  $0 health                       # Check all service health"
            echo "  $0 stop-all                     # Stop all services"
            echo ""
            echo "This script ensures proper service startup coordination and dependency management."
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi