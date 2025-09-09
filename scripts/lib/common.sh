#!/bin/bash
# Common utilities and functions for JStack
# Provides logging, progress tracking, validation, and shared utilities

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════════════════════
# 📝 LOGGING SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize logging system
setup_logging() {
    # Create timestamp for this run
    SCRIPT_START_TIME=$(date '+%Y%m%d_%H%M%S')
    export SCRIPT_START_EPOCH=$(date +%s)
    
    # Try to create log directory, fallback to /tmp if BASE_DIR doesn't exist yet
    if [ -d "$(dirname "$BASE_DIR")" ]; then
        LOG_DIR="$BASE_DIR/logs"
        mkdir -p "$LOG_DIR" 2>/dev/null || {
            LOG_DIR="/tmp/setup-logs"
            mkdir -p "$LOG_DIR"
        }
    else
        LOG_DIR="/tmp/setup-logs"
        mkdir -p "$LOG_DIR"
    fi
    
    # Create timestamped log file
    export SETUP_LOG_FILE="$LOG_DIR/setup_${SCRIPT_START_TIME}.log"
    
    # Clean up old log files (keep last 10)
    if [[ -d "$LOG_DIR" ]]; then
        find "$LOG_DIR" -name "setup_*.log" -type f | sort | head -n -10 | xargs -r rm
    fi
}

# Logging functions
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[INFO]${NC} $1" | tee -a "${SETUP_LOG_FILE:-/dev/null}"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[SUCCESS]${NC} $1" | tee -a "${SETUP_LOG_FILE:-/dev/null}"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARNING]${NC} $1" | tee -a "${SETUP_LOG_FILE:-/dev/null}"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${NC} $1" | tee -a "${SETUP_LOG_FILE:-/dev/null}"
}

log_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════${NC}\n"
}

# Exit handlers
log_failure_exit() {
    local line_no="${1:-unknown}"
    local exit_code="${2:-1}"
    local command="${3:-unknown}"
    
    log_error "Script failed at line $line_no with exit code $exit_code"
    log_error "Failed command: $command"
    log_error "Check the full log at: ${SETUP_LOG_FILE:-unavailable}"
    echo -e "\n${RED}Setup failed. Check logs for details.${NC}"
    exit "$exit_code"
}

log_interrupted_exit() {
    log_warning "Script interrupted by user"
    log_info "Partial installation may exist - run with --uninstall to clean up"
    echo -e "\n${YELLOW}Setup interrupted. Use --uninstall to clean up if needed.${NC}"
    exit 130
}

log_success_exit() {
    local duration=$(($(date +%s) - SCRIPT_START_EPOCH))
    log_success "Setup completed successfully in ${duration}s"
    echo -e "\n${GREEN}🎉 JStack setup completed successfully!${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 PROGRESS TRACKING
# ═══════════════════════════════════════════════════════════════════════════════

# Progress variables
PROGRESS_PID=""
CHECKPOINT_FILE=""
TIMING_DATA=""

# Show progress dots
show_progress_dots() {
    local message="$1"
    local delay="${2:-1}"
    
    echo -n "$message"
    while true; do
        echo -n "."
        sleep "$delay"
    done
}

# Start progress indicator
start_progress() {
    local message="$1"
    show_progress_dots "$message" 0.5 &
    PROGRESS_PID=$!
}

# Stop progress indicator
stop_progress() {
    if [[ -n "$PROGRESS_PID" ]]; then
        kill "$PROGRESS_PID" 2>/dev/null
        wait "$PROGRESS_PID" 2>/dev/null
        PROGRESS_PID=""
        echo " ✓"
    fi
}

# Progress bar
show_progress_bar() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\r["
    printf "%${completed}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' '░'
    printf "] %d%% (%d/%d)" "$percentage" "$current" "$total"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 USER INTERACTION
# ═══════════════════════════════════════════════════════════════════════════════

# Prompt for yes/no response
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"  # Default to 'no' if not specified
    local response
    
    # Format the prompt based on default
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    # Read user input
    read -r -p "$prompt" response
    
    # Handle empty response (use default)
    if [[ -z "$response" ]]; then
        response="$default"
    fi
    
    # Convert to lowercase and check
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$response" == "y" || "$response" == "yes" ]]; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# ⏱️ TIMING SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize timing system
init_timing_system() {
    TIMING_DATA=""
}

# Start section timer
start_section_timer() {
    local section_name="$1"
    echo "$section_name:$(date +%s)" >> /tmp/section_timings_$$
}

# End section timer
end_section_timer() {
    local section_name="$1"
    local start_time=$(grep "^$section_name:" /tmp/section_timings_$$ | cut -d: -f2)
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "$section_name completed in ${duration}s"
    
    # Remove from temp file
    grep -v "^$section_name:" /tmp/section_timings_$$ > /tmp/section_timings_$$.tmp || true
    mv /tmp/section_timings_$$.tmp /tmp/section_timings_$$ 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Safe command execution
safe_execute() {
    local description="$1"
    shift
    local command=("$@")
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_info "[DRY-RUN] Command: ${command[*]}"
        return 0
    fi
    
    log_info "$description"
    if "${command[@]}"; then
        log_success "$description completed"
        return 0
    else
        local exit_code=$?
        log_error "$description failed with exit code $exit_code"
        return $exit_code
    fi
}

# Execute command with detailed output
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_info "[DRY-RUN] Command: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd" >> "${SETUP_LOG_FILE:-/dev/null}" 2>&1; then
        log_success "$description - completed"
        return 0
    else
        local exit_code=$?
        log_error "$description - failed (exit code: $exit_code)"
        return $exit_code
    fi
}

# Docker command wrapper
docker_cmd() {
    local cmd="$1"
    local description="${2:-Docker command}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would execute docker command: $description"
        log_info "[DRY-RUN] Command: $cmd"
        return 0
    fi
    
    if sudo -u "$SERVICE_USER" bash -c "cd $BASE_DIR && $cmd" >> "${SETUP_LOG_FILE:-/dev/null}" 2>&1; then
        return 0
    else
        local exit_code=$?
        log_error "Docker command failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# Wait for service health
wait_for_service_health() {
    local service_name="$1"
    local timeout="${2:-120}"
    local interval="${3:-5}"
    local elapsed=0
    
    log_info "Waiting for $service_name to become healthy (timeout: ${timeout}s)"
    
    while [ $elapsed -lt $timeout ]; do
        if docker_cmd "docker ps --filter name=$service_name --filter health=healthy --format '{{.Names}}'" | grep -q "$service_name"; then
            log_success "$service_name is healthy"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    log_error "$service_name failed to become healthy within ${timeout}s"
    return 1
}

# Password generation
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

generate_secret() {
    openssl rand -base64 64 | tr -d "=+/" | cut -c1-50
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🐳 DOCKER DAEMON FAILURE PREVENTION SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

# Multi-layer Docker daemon health validation
validate_docker_daemon_health() {
    local timeout="${1:-${DOCKER_DAEMON_RESTART_TIMEOUT:-90}}"
    local check_interval="${2:-${DOCKER_HEALTH_CHECK_INTERVAL:-3}}"
    local elapsed=0
    local validation_layers=("basic" "socket" "runtime" "security")
    
    log_info "Validating Docker daemon health (timeout: ${timeout}s)"
    
    while [ $elapsed -lt $timeout ]; do
        local all_layers_passed=true
        
        for layer in "${validation_layers[@]}"; do
            case $layer in
                "basic")
                    # Layer 1: Basic systemd status check
                    if ! systemctl is-active docker &>/dev/null; then
                        log_info "Layer 1 (Basic): Docker service not active"
                        all_layers_passed=false
                        break
                    fi
                    ;;
                "socket")
                    # Layer 2: Docker socket accessibility
                    if ! sudo docker version &>/dev/null; then
                        log_info "Layer 2 (Socket): Docker socket not accessible"
                        all_layers_passed=false
                        break
                    fi
                    ;;
                "runtime")
                    # Layer 3: Container runtime functionality
                    if ! sudo docker info &>/dev/null; then
                        log_info "Layer 3 (Runtime): Docker runtime not functional"
                        all_layers_passed=false
                        break
                    fi
                    ;;
                "security")
                    # Layer 4: Security profile integrity
                    if [[ -f /etc/docker/daemon.json ]] && ! jq . /etc/docker/daemon.json &>/dev/null; then
                        log_info "Layer 4 (Security): Docker daemon.json invalid"
                        all_layers_passed=false
                        break
                    fi
                    ;;
            esac
        done
        
        if $all_layers_passed; then
            log_success "All Docker daemon health layers validated successfully"
            return 0
        fi
        
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done
    
    log_error "Docker daemon health validation failed after ${timeout}s"
    return 1
}

# Pre-restart safety checks
validate_docker_pre_restart() {
    log_info "Performing Docker pre-restart safety checks"
    
    # Check 1: Container management capability
    if ! sudo docker ps --format "table {{.Names}}	{{.Status}}" &>/dev/null; then
        log_warning "Docker container management check failed"
        return 1
    fi
    
    # Check 2: Daemon configuration JSON validity
    if [[ -f /etc/docker/daemon.json ]]; then
        if ! jq . /etc/docker/daemon.json &>/dev/null; then
            log_error "Docker daemon.json contains invalid JSON - restart aborted"
            return 1
        fi
        log_info "Docker daemon.json validation passed"
    fi
    
    # Check 3: Seccomp profile verification (if present)
    if [[ -f /etc/docker/seccomp.json ]]; then
        if ! jq . /etc/docker/seccomp.json &>/dev/null; then
            log_error "Docker seccomp.json contains invalid JSON - restart aborted"
            return 1
        fi
        log_info "Docker seccomp.json validation passed"
    fi
    
    # Check 4: Service user permissions
    if [[ -n "${SERVICE_USER:-}" ]]; then
        if ! groups "$SERVICE_USER" | grep -q docker; then
            log_warning "Service user $SERVICE_USER not in docker group"
        fi
    fi
    
    log_success "Docker pre-restart safety checks completed"
    return 0
}

# Comprehensive safe Docker daemon restart with emergency recovery
safe_docker_daemon_restart() {
    local operation_description="${1:-Docker daemon restart}"
    local max_restart_attempts="${2:-3}"
    local emergency_recovery="${3:-true}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would perform safe Docker daemon restart: $operation_description"
        return 0
    fi
    
    log_section "Safe Docker Daemon Restart: $operation_description"
    
    # Phase 1: Pre-restart validation
    if ! validate_docker_pre_restart; then
        log_error "Pre-restart validation failed - restart aborted"
        return 1
    fi
    
    # Phase 2: Attempt restart with comprehensive recovery
    local attempt=1
    while [[ $attempt -le $max_restart_attempts ]]; do
        log_info "Docker restart attempt $attempt/$max_restart_attempts"
        
        # Perform the restart
        if sudo systemctl restart docker; then
            log_info "Docker service restart command succeeded (attempt $attempt)"
            
            # Phase 3: Post-restart health validation
            if validate_docker_daemon_health; then
                log_success "Docker daemon restart completed successfully"
                return 0
            else
                log_warning "Docker daemon restart succeeded but health validation failed (attempt $attempt)"
            fi
        else
            log_error "Docker service restart command failed (attempt $attempt)"
        fi
        
        # Phase 4: Inter-attempt recovery if not final attempt
        if [[ $attempt -lt $max_restart_attempts ]]; then
            log_info "Preparing for next restart attempt..."
            
            # Stop docker service cleanly
            sudo systemctl stop docker 2>/dev/null || true
            sleep 3
            
            # Clear any stale docker processes
            sudo pkill -f dockerd 2>/dev/null || true
            sleep 2
            
            # Clean up docker runtime state if needed
            if [[ -d /var/run/docker ]]; then
                sudo rm -rf /var/run/docker/runtime-runc/moby/* 2>/dev/null || true
            fi
            
            log_info "Inter-attempt cleanup completed"
        fi
        
        ((attempt++))
    done
    
    # Phase 5: Emergency recovery procedures
    if [[ "$emergency_recovery" == "true" ]]; then
        log_warning "All restart attempts failed - initiating emergency recovery"
        
        # Emergency step 1: Full service reset
        log_info "Emergency recovery: Full Docker service reset"
        sudo systemctl stop docker 2>/dev/null || true
        sleep 5
        
        # Emergency step 2: Clean stale processes and state
        log_info "Emergency recovery: Cleaning stale Docker processes"
        sudo pkill -9 -f dockerd 2>/dev/null || true
        sudo pkill -9 -f docker-containerd 2>/dev/null || true
        sleep 3
        
        # Emergency step 3: Remove problematic runtime state
        log_info "Emergency recovery: Clearing Docker runtime state"
        sudo rm -rf /var/run/docker/* 2>/dev/null || true
        sudo rm -rf /var/lib/docker/tmp/* 2>/dev/null || true
        
        # Emergency step 4: Reset daemon configuration if corrupted
        if [[ -f /etc/docker/daemon.json ]] && ! jq . /etc/docker/daemon.json &>/dev/null; then
            log_warning "Emergency recovery: Backing up corrupted daemon.json"
            sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.corrupted.$(date +%s)" 2>/dev/null || true
            sudo rm -f /etc/docker/daemon.json
        fi
        
        # Emergency step 5: Final restart attempt
        log_info "Emergency recovery: Final Docker restart attempt"
        if sudo systemctl start docker && validate_docker_daemon_health 60 2; then
            log_success "Emergency recovery successful - Docker daemon restored"
            return 0
        else
            log_error "Emergency recovery failed - Docker daemon could not be restored"
            
            # Provide detailed diagnostic information
            log_error "Docker diagnostic information:"
            log_error "- Service status: $(systemctl is-active docker 2>/dev/null || echo 'unknown')"
            log_error "- Service enabled: $(systemctl is-enabled docker 2>/dev/null || echo 'unknown')"
            log_error "- Docker socket: $([[ -S /var/run/docker.sock ]] && echo 'present' || echo 'missing')"
            log_error "- Free disk space: $(df -h /var/lib/docker 2>/dev/null | tail -1 | awk '{print $4}' || echo 'unknown')"
            log_error "- Memory usage: $(free -h | grep '^Mem:' | awk '{print $3"/"$2}' || echo 'unknown')"
            
            return 1
        fi
    else
        log_error "Docker daemon restart failed after $max_restart_attempts attempts"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔒 SECURITY UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# File operations with safety checks
validate_temp_file() {
    local file="$1"
    
    # Check if file exists and is writable
    if [[ ! -f "$file" ]]; then
        log_error "Temporary file does not exist: $file"
        return 1
    fi
    
    # Check if file is in a safe location
    if [[ ! "$file" =~ ^/tmp/ ]] && [[ ! "$file" =~ ^"$BASE_DIR"/ ]]; then
        log_error "Unsafe file location: $file"
        return 1
    fi
    
    return 0
}

# Safe move operation
safe_mv() {
    local src="$1"
    local dst="$2"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would move $src to $dst"
        return 0
    fi
    
    if validate_temp_file "$src" && mv "$src" "$dst"; then
        log_info "Successfully moved $src to $dst"
        return 0
    else
        log_error "Failed to move $src to $dst"
        return 1
    fi
}

# Safe chmod operation
safe_chmod() {
    local permissions="$1"
    local file="$2"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would set permissions $permissions on $file"
        return 0
    fi
    
    if chmod "$permissions" "$file"; then
        log_info "Set permissions $permissions on $file"
        return 0
    else
        log_error "Failed to set permissions $permissions on $file"
        return 1
    fi
}

# Safe chown operation
safe_chown() {
    local ownership="$1"
    local file="$2"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would set ownership $ownership on $file"
        return 0
    fi
    
    if chown "$ownership" "$file"; then
        log_info "Set ownership $ownership on $file"
        return 0
    else
        log_error "Failed to set ownership $ownership on $file"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🏗️ SITE REGISTRY MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize site registry structure
init_site_registry() {
    local registry_path="$1"
    local registry_dir=$(dirname "$registry_path")
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would initialize site registry at: $registry_path"
        return 0
    fi
    
    # Create registry directory if it doesn't exist
    if [[ ! -d "$registry_dir" ]]; then
        if mkdir -p "$registry_dir"; then
            log_info "Created site registry directory: $registry_dir"
        else
            log_error "Failed to create site registry directory: $registry_dir"
            return 1
        fi
    fi
    
    # Create default site registry if it doesn't exist
    if [[ ! -f "$registry_path" ]]; then
        local default_registry=$(cat << 'EOF'
{
  "sites": {},
  "compliance_profiles": {
    "default": {
      "frameworks": ["SOC2", "GDPR", "ISO27001"],
      "monitoring_enabled": true,
      "audit_retention": "90d",
      "report_schedule": "0 2 * * 0"
    },
    "strict": {
      "frameworks": ["SOC2", "GDPR", "ISO27001", "HIPAA", "PCI-DSS"],
      "monitoring_enabled": true,
      "audit_retention": "365d",
      "report_schedule": "0 1 * * *"
    }
  },
  "metadata": {
    "version": "1.0",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF
)
        
        if echo "$default_registry" > "$registry_path"; then
            log_success "Created default site registry: $registry_path"
        else
            log_error "Failed to create default site registry: $registry_path"
            return 1
        fi
    fi
    
    return 0
}

# Load site registry from file
load_site_registry() {
    local registry_path="${1:-$SITE_REGISTRY_PATH}"
    
    if [[ ! -f "$registry_path" ]]; then
        log_warning "Site registry not found: $registry_path"
        return 1
    fi
    
    if ! jq . "$registry_path" > /dev/null 2>&1; then
        log_error "Site registry contains invalid JSON: $registry_path"
        return 1
    fi
    
    return 0
}

# Add site to registry
add_site_to_registry() {
    local domain="$1"
    local compliance_profile="${2:-default}"
    local template_name="${3:-custom}"
    local registry_path="${4:-$SITE_REGISTRY_PATH}"
    
    if [[ -z "$domain" ]]; then
        log_error "Domain is required for site registration"
        return 1
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would add site to registry: $domain"
        return 0
    fi
    
    # Initialize registry if it doesn't exist
    if ! init_site_registry "$registry_path"; then
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for site registry management"
        return 1
    fi
    
    # Create site entry
    local current_date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local site_entry=$(cat << EOF
{
  "domain": "$domain",
  "template": "$template_name",
  "subdomains": {
    "supabase": "${SUPABASE_SUBDOMAIN:-supabase}.$domain",
    "studio": "${STUDIO_SUBDOMAIN:-studio}.$domain",
    "n8n": "${N8N_SUBDOMAIN:-n8n}.$domain"
  },
  "ssl_config": "/etc/ssl/certs/$domain/",
  "nginx_config": "/etc/nginx/sites-available/$domain.conf",
  "status": "active",
  "added_date": "$current_date",
  "compliance_profile": "$compliance_profile"
}
EOF
)
    
    # Add site to registry
    local temp_registry=$(mktemp)
    if jq --argjson site "$site_entry" \
          --arg domain "$domain" \
          --arg updated "$current_date" \
          '.sites[$domain] = $site | .metadata.last_updated = $updated' \
          "$registry_path" > "$temp_registry"; then
        
        if mv "$temp_registry" "$registry_path"; then
            log_success "Added site to registry: $domain"
            return 0
        else
            log_error "Failed to update site registry file"
            rm -f "$temp_registry"
            return 1
        fi
    else
        log_error "Failed to add site to registry JSON"
        rm -f "$temp_registry"
        return 1
    fi
}

# Remove site from registry
remove_site_from_registry() {
    local domain="$1"
    local registry_path="${2:-$SITE_REGISTRY_PATH}"
    
    if [[ -z "$domain" ]]; then
        log_error "Domain is required for site removal"
        return 1
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would remove site from registry: $domain"
        return 0
    fi
    
    if [[ ! -f "$registry_path" ]]; then
        log_warning "Site registry not found: $registry_path"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for site registry management"
        return 1
    fi
    
    # Remove site from registry
    local temp_registry=$(mktemp)
    if jq --arg domain "$domain" \
          'del(.sites[$domain]) | .metadata.last_updated = now | strftime("%Y-%m-%dT%H:%M:%SZ")' \
          "$registry_path" > "$temp_registry"; then
        
        if mv "$temp_registry" "$registry_path"; then
            log_success "Removed site from registry: $domain"
            return 0
        else
            log_error "Failed to update site registry file"
            rm -f "$temp_registry"
            return 1
        fi
    else
        log_error "Failed to remove site from registry JSON"
        rm -f "$temp_registry"
        return 1
    fi
}

# List all sites in registry
list_sites_in_registry() {
    local registry_path="${1:-$SITE_REGISTRY_PATH}"
    
    if [[ ! -f "$registry_path" ]]; then
        log_warning "Site registry not found: $registry_path"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for site registry management"
        return 1
    fi
    
    echo "Registered Sites:"
    jq -r '.sites | to_entries[] | "  \(.key) (\(.value.status)) - \(.value.compliance_profile) profile"' "$registry_path"
    
    return 0
}

# Get site information from registry
get_site_from_registry() {
    local domain="$1"
    local registry_path="${2:-$SITE_REGISTRY_PATH}"
    
    if [[ -z "$domain" ]]; then
        log_error "Domain is required for site lookup"
        return 1
    fi
    
    if [[ ! -f "$registry_path" ]]; then
        log_warning "Site registry not found: $registry_path"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for site registry management"
        return 1
    fi
    
    # Get site information
    local site_info=$(jq --arg domain "$domain" '.sites[$domain]' "$registry_path")
    
    if [[ "$site_info" == "null" ]]; then
        log_warning "Site not found in registry: $domain"
        return 1
    fi
    
    echo "$site_info"
    return 0
}

# Backup site registry
backup_site_registry() {
    local registry_path="${1:-$SITE_REGISTRY_PATH}"
    local backup_dir="${2:-$(dirname "$registry_path")/backups}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would backup site registry"
        return 0
    fi
    
    if [[ ! -f "$registry_path" ]]; then
        log_warning "Site registry not found for backup: $registry_path"
        return 1
    fi
    
    # Create backup directory
    if [[ ! -d "$backup_dir" ]]; then
        if mkdir -p "$backup_dir"; then
            log_info "Created backup directory: $backup_dir"
        else
            log_error "Failed to create backup directory: $backup_dir"
            return 1
        fi
    fi
    
    # Create timestamped backup
    local backup_file="$backup_dir/sites_$(date +%Y%m%d_%H%M%S).json"
    
    if cp "$registry_path" "$backup_file"; then
        log_success "Site registry backed up to: $backup_file"
        
        # Clean up old backups (keep last SITE_REGISTRY_BACKUP_RETENTION)
        local retention="${SITE_REGISTRY_BACKUP_RETENTION:-30}"
        find "$backup_dir" -name "sites_*.json" -type f | sort | head -n -"$retention" | xargs -r rm
        
        return 0
    else
        log_error "Failed to backup site registry"
        return 1
    fi
}

# Main function for testing
main() {
    setup_logging
    log_info "Common library loaded successfully"
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi