#!/bin/bash
# Common Service Utilities for JStack
# Shared functions for service modules to reduce duplication

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 COMMON SERVICE UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Wait for a service to be healthy with configurable timeout and intervals
wait_for_service_health() {
    local service_name="$1"
    local timeout="${2:-60}"
    local check_interval="${3:-5}"
    local elapsed=0
    
    log_info "Waiting for $service_name to be healthy (timeout: ${timeout}s)"
    
    while [[ $elapsed -lt $timeout ]]; do
        if docker inspect "$service_name" &>/dev/null; then
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "no-health-check")
            
            if [[ "$health_status" == "healthy" ]]; then
                log_success "$service_name is healthy"
                return 0
            elif [[ "$health_status" == "no-health-check" ]]; then
                # If no health check is configured, check if container is running
                local running_status=$(docker inspect --format='{{.State.Running}}' "$service_name" 2>/dev/null || echo "false")
                if [[ "$running_status" == "true" ]]; then
                    log_success "$service_name is running (no health check configured)"
                    return 0
                fi
            fi
        else
            log_warning "$service_name container not found"
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        echo -n "."
    done
    
    echo ""
    log_error "$service_name failed to become healthy within ${timeout} seconds"
    return 1
}

# Execute docker command with proper error handling
docker_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd"; then
        log_success "$description completed"
        return 0
    else
        log_error "$description failed"
        return 1
    fi
}

# Check if a service container exists and is running
is_service_running() {
    local service_name="$1"
    
    if docker ps --filter name="$service_name" --filter status=running --quiet | grep -q .; then
        return 0
    else
        return 1
    fi
}

# Get service container status
get_service_status() {
    local service_name="$1"
    
    if docker inspect "$service_name" &>/dev/null; then
        local running=$(docker inspect --format='{{.State.Running}}' "$service_name" 2>/dev/null || echo "false")
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service_name" 2>/dev/null || echo "no-health-check")
        
        if [[ "$running" == "true" ]]; then
            if [[ "$health" == "healthy" ]]; then
                echo "running-healthy"
            elif [[ "$health" == "unhealthy" ]]; then
                echo "running-unhealthy"
            else
                echo "running-no-health-check"
            fi
        else
            echo "stopped"
        fi
    else
        echo "not-found"
    fi
}

# Create service directories with proper ownership
create_service_directory() {
    local service_dir="$1"
    local subdirs="$2"
    
    log_info "Creating service directory: $service_dir"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $service_dir" "Create service directory"
    
    if [[ -n "$subdirs" ]]; then
        IFS=',' read -ra SUBDIRS <<< "$subdirs"
        for subdir in "${SUBDIRS[@]}"; do
            execute_cmd "sudo -u $SERVICE_USER mkdir -p $service_dir/$subdir" "Create subdirectory: $subdir"
        done
    fi
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$service_dir" "Set service directory ownership"
}

# Install configuration file with proper permissions
install_service_config() {
    local temp_file="$1"
    local target_path="$2"
    local description="$3"
    local permissions="${4:-600}"
    
    safe_mv "$temp_file" "$target_path" "$description"
    safe_chmod "$permissions" "$target_path" "Set config permissions"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$target_path" "Set config ownership"
}

# Start service with docker-compose
start_service_with_compose() {
    local service_dir="$1"
    local service_name="$2"
    local env_file="${3:-.env}"
    
    if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
        log_error "Docker compose file not found: $service_dir/docker-compose.yml"
        return 1
    fi
    
    if [[ ! -f "$service_dir/$env_file" ]]; then
        log_error "Environment file not found: $service_dir/$env_file"
        return 1
    fi
    
    log_info "Starting $service_name service"
    docker_cmd "cd $service_dir && docker-compose --env-file $env_file up -d" "Start $service_name containers"
    
    return $?
}

# Stop service with docker-compose
stop_service_with_compose() {
    local service_dir="$1"
    local service_name="$2"
    
    if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
        log_warning "$service_name compose file not found - may already be cleaned up"
        return 0
    fi
    
    log_info "Stopping $service_name service"
    docker_cmd "cd $service_dir && docker-compose down" "Stop $service_name containers"
    
    return $?
}

# Show service logs
show_service_logs() {
    local container_name="$1"
    local lines="${2:-50}"
    
    if docker inspect "$container_name" &>/dev/null; then
        log_info "Showing last $lines lines for $container_name:"
        docker logs --tail="$lines" "$container_name"
    else
        log_error "Container $container_name not found"
        return 1
    fi
}

# Generate secure password for services
generate_service_password() {
    local length="${1:-32}"
    generate_password "$length"
}

# Generate secure secret for services  
generate_service_secret() {
    local length="${1:-64}"
    generate_secret "$length"
}

# Validate service configuration
validate_service_config() {
    local config_file="$1"
    local required_vars="$2"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    log_info "Validating service configuration: $config_file"
    
    IFS=',' read -ra VARS <<< "$required_vars"
    local missing_vars=()
    
    for var in "${VARS[@]}"; do
        if ! grep -q "^${var}=" "$config_file"; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required configuration variables: ${missing_vars[*]}"
        return 1
    fi
    
    log_success "Service configuration validation passed"
    return 0
}

# Check service prerequisites
check_service_prerequisites() {
    local service_name="$1"
    local required_services="$2"
    
    log_info "Checking prerequisites for $service_name"
    
    # Check if required services are provided
    if [[ -n "$required_services" ]]; then
        IFS=',' read -ra SERVICES <<< "$required_services"
        local missing_services=()
        
        for service in "${SERVICES[@]}"; do
            if ! is_service_running "$service"; then
                missing_services+=("$service")
            fi
        done
        
        if [[ ${#missing_services[@]} -gt 0 ]]; then
            log_error "$service_name requires these services to be running: ${missing_services[*]}"
            return 1
        fi
    fi
    
    # Check Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not available - required for $service_name"
        return 1
    fi
    
    # Check Docker Compose is available
    if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
        log_error "Docker Compose is not available - required for $service_name"
        return 1
    fi
    
    # Check required networks exist
    for network in "$PUBLIC_TIER" "$PRIVATE_TIER"; do
        if ! docker network inspect "$network" &> /dev/null; then
            log_error "Required Docker network not found: $network"
            log_info "Run system setup first to create required networks"
            return 1
        fi
    done
    
    log_success "Prerequisites check passed for $service_name"
    return 0
}

# Cleanup service resources
cleanup_service_resources() {
    local service_name="$1"
    local service_dir="$2"
    local remove_volumes="${3:-false}"
    
    log_section "Cleaning up $service_name resources"
    
    # Stop and remove containers
    if [[ -f "$service_dir/docker-compose.yml" ]]; then
        if [[ "$remove_volumes" == "true" ]]; then
            docker_cmd "cd $service_dir && docker-compose down -v" "Remove $service_name containers and volumes"
        else
            docker_cmd "cd $service_dir && docker-compose down" "Remove $service_name containers"
        fi
    fi
    
    # Remove service directory if requested
    if [[ "$remove_volumes" == "true" && -d "$service_dir" ]]; then
        execute_cmd "rm -rf $service_dir" "Remove $service_name directory"
    fi
    
    log_success "$service_name cleanup completed"
}

# Export functions for use by other scripts
export -f wait_for_service_health
export -f docker_cmd
export -f is_service_running
export -f get_service_status
export -f create_service_directory
export -f install_service_config
export -f start_service_with_compose
export -f stop_service_with_compose
export -f show_service_logs
export -f generate_service_password
export -f generate_service_secret
export -f validate_service_config
export -f check_service_prerequisites
export -f cleanup_service_resources

# Main function for testing utilities
main() {
    case "${1:-help}" in
        "test-health")
            service_name="${2:-nginx-proxy}"
            timeout="${3:-30}"
            wait_for_service_health "$service_name" "$timeout"
            ;;
        "check-running")
            service_name="${2:-nginx-proxy}"
            if is_service_running "$service_name"; then
                echo "$service_name is running"
            else
                echo "$service_name is not running"
            fi
            ;;
        "get-status")
            service_name="${2:-nginx-proxy}"
            status=$(get_service_status "$service_name")
            echo "$service_name status: $status"
            ;;
        "show-logs")
            service_name="${2:-nginx-proxy}"
            lines="${3:-20}"
            show_service_logs "$service_name" "$lines"
            ;;
        "help"|*)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  test-health SERVICE [TIMEOUT]  - Test service health"
            echo "  check-running SERVICE          - Check if service is running"
            echo "  get-status SERVICE             - Get detailed service status"
            echo "  show-logs SERVICE [LINES]      - Show service logs"
            echo "  help                           - Show this help"
            echo ""
            echo "This module provides common utilities for service management."
            echo "Most functions are meant to be sourced by other service modules."
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi