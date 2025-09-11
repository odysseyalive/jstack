#!/bin/bash
# Validation utilities for JStack
# Handles DNS, environment, and system validation

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${SCRIPT_DIR}/common.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 DNS VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate DNS configuration with parallel checks
validate_dns_parallel() {
    log_section "Validating DNS Configuration"
    
    local domains=("$DOMAIN" "${SUPABASE_SUBDOMAIN}.${DOMAIN}" "${STUDIO_SUBDOMAIN}.${DOMAIN}" "${N8N_SUBDOMAIN}.${DOMAIN}")
    local server_ipv4 server_ipv6
    
    # Get server IP addresses
    server_ipv4=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || echo "")
    server_ipv6=$(curl -6 -s --max-time 5 ifconfig.me 2>/dev/null || curl -6 -s --max-time 5 icanhazip.com 2>/dev/null || echo "")
    
    if [[ -n "$server_ipv4" ]]; then
        log_info "Server IPv4: $server_ipv4"
    else
        log_warning "Could not determine server IPv4 address"
    fi
    
    if [[ -n "$server_ipv6" ]]; then
        log_info "Server IPv6: $server_ipv6"
    else
        log_info "Server IPv6: Not available"
    fi
    
    # Validate each domain
    local failed_domains=()
    for domain in "${domains[@]}"; do
        if ! validate_single_domain "$domain" "$server_ipv4" "$server_ipv6"; then
            failed_domains+=("$domain")
        fi
    done
    
    if [[ ${#failed_domains[@]} -gt 0 ]]; then
        log_error "DNS validation failed for domains: ${failed_domains[*]}"
        log_error "Please ensure all domains have A records pointing to your server IP"
        return 1
    fi
    
    log_success "All DNS records validated successfully"
    return 0
}

# Validate a single domain
validate_single_domain() {
    local domain="$1"
    local server_ipv4="$2"
    local server_ipv6="$3"
    
    log_info "Checking DNS for $domain"
    
    # Check A record
    local resolved_ipv4=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -n1)
    
    if [[ -n "$resolved_ipv4" ]]; then
        if [[ "$resolved_ipv4" == "$server_ipv4" ]]; then
            log_success "$domain A record: $resolved_ipv4 ✓"
        else
            log_warning "$domain A record: $resolved_ipv4 (expected: $server_ipv4)"
            return 1
        fi
    else
        log_error "$domain: No A record found"
        return 1
    fi
    
    return 0
}

# Validate DNS configuration (legacy function name for compatibility)
validate_dns_configuration() {
    validate_dns_parallel "$@"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚪 PORT CONFLICT RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════════

# Check if a port has a conflict
check_port_conflict() {
    local port="$1"
    netstat -tuln 2>/dev/null | grep -q ":$port "
}

# Get detailed information about what's using a port
get_port_usage_info() {
    local port="$1"
    local service_info=""
    local process_info=""
    local pid=""
    local service_name=""
    
    # Get network connection info
    service_info=$(netstat -tuln 2>/dev/null | grep ":$port " | head -1)
    
    # Get process information if lsof is available
    if command_exists lsof; then
        process_info=$(lsof -i :$port 2>/dev/null | grep LISTEN | head -1)
        if [[ -n "$process_info" ]]; then
            pid=$(echo "$process_info" | awk '{print $2}')
            service_name=$(echo "$process_info" | awk '{print $1}')
        fi
    fi
    
    # Try alternative methods if lsof didn't work
    if [[ -z "$pid" ]] && command_exists ss; then
        local ss_info=$(ss -tlnp 2>/dev/null | grep ":$port ")
        if [[ -n "$ss_info" ]]; then
            pid=$(echo "$ss_info" | sed 's/.*pid=\([0-9]*\).*/\1/' | head -1)
        fi
    fi
    
    # Get service name from systemctl if we have a PID
    if [[ -n "$pid" ]] && command_exists systemctl; then
        local systemd_service=$(systemctl status "$pid" 2>/dev/null | grep "Active:" | head -1)
        if [[ -n "$systemd_service" ]]; then
            service_name=$(systemctl status "$pid" 2>/dev/null | head -1 | sed 's/.*● \([^.]*\).*/\1/')
        fi
    fi
    
    echo "service_info:$service_info|process_info:$process_info|pid:$pid|service_name:$service_name"
}

# Attempt to automatically resolve port conflicts  
resolve_port_conflict() {
    local port="$1"
    
    log_warning "Port $port conflict detected - attempting resolution"
    
    # Get detailed port usage information
    local port_usage_info=$(get_port_usage_info "$port")
    local service_info=$(echo "$port_usage_info" | cut -d'|' -f1 | cut -d':' -f2)
    local process_info=$(echo "$port_usage_info" | cut -d'|' -f2 | cut -d':' -f2)
    local pid=$(echo "$port_usage_info" | cut -d'|' -f3 | cut -d':' -f2)
    local service_name=$(echo "$port_usage_info" | cut -d'|' -f4 | cut -d':' -f2)
    
    # Display conflict information
    log_info "Port $port conflict details:"
    [[ -n "$service_info" ]] && log_info "  Network: $service_info"
    [[ -n "$process_info" ]] && log_info "  Process: $process_info"
    [[ -n "$pid" ]] && log_info "  PID: $pid"
    [[ -n "$service_name" ]] && log_info "  Service: $service_name"
    
    # Check for force installation flag
    if [[ "${FORCE_INSTALL:-false}" == "true" ]]; then
        log_warning "Force install enabled - proceeding despite port $port conflict"
        log_warning "WARNING: This may cause service conflicts during operation"
        return 0
    fi
    
    # Check for interactive mode availability
    if [[ "${INTERACTIVE_MODE:-true}" != "true" || ! -t 0 ]]; then
        log_error "Port $port is in use and interactive resolution not available"
        log_info "Resolution options:"
        log_info "  1. Stop the conflicting service manually"
        [[ -n "$service_name" ]] && log_info "     sudo systemctl stop $service_name"
        [[ -n "$pid" ]] && log_info "     sudo kill $pid"
        log_info "  2. Use --force flag to continue anyway (not recommended)"
        log_info "  3. Configure the conflicting service to use a different port"
        return 1
    fi
    
    # Interactive resolution
    echo ""
    log_info "PORT CONFLICT RESOLUTION OPTIONS:"
    log_info "================================="
    echo ""
    echo "  1) Stop the conflicting service (recommended)"
    echo "  2) Continue anyway (may cause conflicts)"
    echo "  3) Abort installation"
    echo ""
    
    read -p "Choose resolution option [1-3]: " -r choice
    
    case "$choice" in
        "1")
            log_info "Attempting to stop conflicting service..."
            local stopped=false
            
            # Try stopping by systemd service name
            if [[ -n "$service_name" ]] && systemctl is-active "$service_name" &>/dev/null; then
                if sudo systemctl stop "$service_name"; then
                    log_success "Service '$service_name' stopped"
                    stopped=true
                fi
            fi
            
            # Try stopping by PID if service stop didn't work
            if [[ "$stopped" == "false" && -n "$pid" ]]; then
                if sudo kill "$pid" 2>/dev/null; then
                    log_success "Process $pid terminated"
                    stopped=true
                fi
            fi
            
            if [[ "$stopped" == "true" ]]; then
                sleep 2
                if ! check_port_conflict "$port"; then
                    log_success "Port $port is now available"
                    return 0
                else
                    log_error "Port $port still in use after stopping service"
                    return 1
                fi
            else
                log_error "Failed to stop conflicting service"
                log_info "Please stop it manually and retry installation"
                return 1
            fi
            ;;
        "2")
            log_warning "Continuing with port $port conflict"
            log_warning "WARNING: This may cause service conflicts during operation"
            return 0
            ;;
        "3")
            log_info "Installation aborted by user"
            return 1
            ;;
        *)
            log_error "Invalid choice: $choice"
            return 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 ENVIRONMENT VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate environment prerequisites
validate_environment() {
    log_section "Environment Validation"
    
    local validation_errors=()
    
    # Root check moved to validate_sudo_access() function
    
    # Check for required commands (excluding docker-compose which has dual compatibility)
    local required_commands=("docker" "curl" "dig" "openssl" "gpg")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            validation_errors+=("Required command not found: $cmd")
        fi
    done
    
    # Check Docker Compose availability using unified detection function
    if ! validate_docker_compose_availability; then
        validation_errors+=("Docker Compose not available - install Docker Desktop or docker-compose-plugin")
    fi
    
    # Check disk space (require at least 10GB free)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=$((10 * 1024 * 1024)) # 10GB in KB
    if [[ $available_space -lt $required_space ]]; then
        validation_errors+=("Insufficient disk space. Required: 10GB, Available: $((available_space / 1024 / 1024))GB")
    fi
    
    # Check memory (recommend at least 4GB)
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 4096 ]]; then
        log_warning "Low memory detected: ${total_mem}MB. Recommended: 4GB+"
    fi
    
    # Check if service user exists
    if ! id "$SERVICE_USER" &>/dev/null; then
        log_warning "Service user does not exist: $SERVICE_USER"
        log_info "This will be created automatically during setup"
    fi
    
    # Validate configuration
    if [[ "$DOMAIN" == "example.com" ]] || [[ -z "$DOMAIN" ]]; then
        validation_errors+=("DOMAIN must be set to your actual domain in jstack.config")
    fi
    
    if [[ "$EMAIL" == "admin@example.com" ]] || [[ -z "$EMAIL" ]]; then
        validation_errors+=("EMAIL must be set to your actual email in jstack.config")
    fi
    
    # Check if ports are available with enhanced conflict resolution
    local required_ports=(80 443)
    for port in "${required_ports[@]}"; do
        if check_port_conflict "$port"; then
            if ! resolve_port_conflict "$port"; then
                validation_errors+=("Port $port conflict could not be resolved")
            fi
        fi
    done
    
    # Report validation results
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_error "Environment validation failed:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_success "Environment validation passed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔐 SUDO ACCESS VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate sudo access - fails fast to prevent installation issues
validate_sudo_access() {
    log_section "Sudo Access Validation"
    
    local sudo_errors=()
    
    # Check if running as root (should not be)
    if [[ $EUID -eq 0 ]]; then
        sudo_errors+=("Script should not be run as root. Run as a regular user with sudo access.")
        log_error "Running as root is not supported"
        log_info "Please run as a regular user with sudo access"
        return 1
    fi
    
    # Check if user has any sudo access
    if ! sudo -v 2>/dev/null; then
        sudo_errors+=("User $USER has no sudo access. Please ensure user is in sudoers group.")
        log_error "No sudo access detected for user: $USER"
        log_info ""
        log_info "REMEDIATION OPTIONS:"
        log_info "===================="
        log_info ""
        log_info "Option 1: Add user to sudoers group (requires admin access):"
        log_info "  sudo usermod -aG sudo $USER"
        log_info "  # Then logout and login again"
        log_info ""
        log_info "Option 2: Ask system administrator to grant sudo access"
        log_info ""
        log_info "Option 3: Run installation from a user account that already has sudo access"
        log_info ""
        return 1
    fi
    
    # Check if user has passwordless sudo access
    if ! sudo -n true 2>/dev/null; then
        log_warning "User $USER has sudo access but requires password"
        log_info ""
        log_info "For automated installation, passwordless sudo is recommended."
        log_info ""
        log_info "REMEDIATION OPTIONS:"
        log_info "===================="
        log_info ""
        log_info "Option 1: Configure passwordless sudo automatically (RECOMMENDED):"
        log_info "  ./jstack.sh --configure-sudo"
        log_info ""
        log_info "Option 2: Force installation with password prompts (NOT RECOMMENDED):"
        log_info "  ./jstack.sh --force-install"
        log_info ""
        log_info "Option 3: Manual sudo configuration:"
        log_info "  See documentation for manual sudoers configuration"
        log_info ""
        
        # Check for non-interactive mode or force install flag
        if [[ "${FORCE_INSTALL:-false}" == "true" ]]; then
            log_info "Force install mode detected - continuing with password-based sudo"
            return 0
        fi
        
        # In non-interactive environments, fail fast
        if [[ ! -t 0 ]]; then
            log_error "Non-interactive mode detected and passwordless sudo not configured"
            log_info "Use one of the remediation options above and retry installation"
            return 1
        fi
        
        # Interactive prompt for user choice
        echo ""
        echo "Would you like to:"
        echo "1) Configure passwordless sudo now (recommended)"
        echo "2) Continue with password prompts (not recommended for automation)"
        echo "3) Exit and configure manually"
        echo ""
        read -p "Choose option [1-3]: " -r choice
        
        case "$choice" in
            1)
                log_info "Launching sudo configuration..."
                if bash "${PROJECT_ROOT}/scripts/core/setup.sh" sudo; then
                    log_success "Passwordless sudo configured successfully"
                    return 0
                else
                    log_error "Sudo configuration failed"
                    return 1
                fi
                ;;
            2)
                log_warning "Continuing with password-based sudo (may require multiple password entries)"
                return 0
                ;;
            3|*)
                log_info "Installation cancelled. Please configure sudo access first:"
                log_info "  ./jstack.sh --configure-sudo"
                return 1
                ;;
        esac
    else
        log_success "User $USER has passwordless sudo access"
    fi
    
    # Report validation results
    if [[ ${#sudo_errors[@]} -gt 0 ]]; then
        log_error "Sudo validation failed:"
        for error in "${sudo_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 👤 USER CONFIGURATION VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate user configuration
validate_user_configuration() {
    log_section "User Configuration Validation"
    
    local config_errors=()
    
    # Validate domain format
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
        config_errors+=("Invalid domain format: $DOMAIN")
    fi
    
    # Validate email format
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        config_errors+=("Invalid email format: $EMAIL")
    fi
    
    # Validate subdomain formats
    for subdomain in "$SUPABASE_SUBDOMAIN" "$STUDIO_SUBDOMAIN" "$N8N_SUBDOMAIN"; do
        if [[ ! "$subdomain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
            config_errors+=("Invalid subdomain format: $subdomain")
        fi
    done
    
    # Validate resource limits
    if [[ ! "$POSTGRES_MEMORY_LIMIT" =~ ^[0-9]+[MGmg]$ ]]; then
        config_errors+=("Invalid memory limit format: $POSTGRES_MEMORY_LIMIT")
    fi
    
    # Validate numeric settings
    if [[ ! "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        config_errors+=("Invalid backup retention days: $BACKUP_RETENTION_DAYS")
    fi
    
    if [[ ! "$POSTGRES_MAX_CONNECTIONS" =~ ^[0-9]+$ ]]; then
        config_errors+=("Invalid max connections: $POSTGRES_MAX_CONNECTIONS")
    fi
    
    # Validate boolean settings
    for setting in "$ENABLE_INTERNAL_SSL" "$UFW_ENABLED" "$BACKUP_ENCRYPTION"; do
        if [[ "$setting" != "true" && "$setting" != "false" ]]; then
            config_errors+=("Invalid boolean setting: $setting (must be 'true' or 'false')")
        fi
    done
    
    # Report validation results
    if [[ ${#config_errors[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        for error in "${config_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_success "User configuration validation passed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🏥 SYSTEM HEALTH VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Check system prerequisites
check_prerequisites() {
    log_section "System Prerequisites Check"
    
    local prereq_errors=()
    
    # Check OS version
    if [[ -f /etc/debian_version ]]; then
        local debian_version=$(cat /etc/debian_version)
        log_info "Debian version: $debian_version"
        if [[ ! "$debian_version" =~ ^12\. ]]; then
            log_warning "This script is optimized for Debian 12. Current version: $debian_version"
        fi
    else
        log_warning "Non-Debian system detected. This script is optimized for Debian 12."
    fi
    
    # Check systemd
    if ! systemctl --version &>/dev/null; then
        prereq_errors+=("systemd is required but not available")
    fi
    
    # Sudo access check moved to validate_sudo_access() function
    
    # Check if user has systemd linger enabled
    if [[ ! -f "/var/lib/systemd/linger/$USER" ]]; then
        log_warning "Systemd linger not enabled for user $USER"
        log_info "This will be enabled automatically during setup"
    fi
    
    # Check Docker installation
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version)
        log_info "Docker found: $docker_version"
    else
        log_info "Docker not found - will be installed during setup"
    fi
    
    # Check available entropy for secret generation
    if [[ -r /proc/sys/kernel/random/entropy_avail ]]; then
        local entropy=$(cat /proc/sys/kernel/random/entropy_avail)
        if [[ $entropy -lt 1000 ]]; then
            log_warning "Low system entropy: $entropy. Consider installing haveged or rng-tools"
        fi
    fi
    
    # Report results
    if [[ ${#prereq_errors[@]} -gt 0 ]]; then
        log_error "Prerequisites check failed:"
        for error in "${prereq_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_success "System prerequisites check passed"
    return 0
}

# Main validation function
main() {
    source "${SCRIPT_DIR}/config.sh"
    
    # Run all validations
    if validate_environment && \
       validate_user_configuration && \
       check_prerequisites && \
       validate_dns_configuration; then
        log_success "All validations passed successfully"
        return 0
    else
        log_error "One or more validations failed"
        return 1
    fi
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi