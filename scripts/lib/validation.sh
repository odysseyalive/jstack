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
# 🔧 ENVIRONMENT VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate environment prerequisites
validate_environment() {
    log_section "Environment Validation"
    
    local validation_errors=()
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        validation_errors+=("Script should not be run as root. Run as a regular user with sudo access.")
    fi
    
    # Check for required commands (excluding docker-compose which has dual compatibility)
    local required_commands=("docker" "curl" "dig" "openssl" "gpg")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            validation_errors+=("Required command not found: $cmd")
        fi
    done
    
    # Check Docker Compose availability (accept either variant)
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        validation_errors+=("Docker Compose not available - install Docker Desktop or standalone version")
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
        validation_errors+=("Service user does not exist: $SERVICE_USER")
    fi
    
    # Validate configuration
    if [[ "$DOMAIN" == "example.com" ]] || [[ -z "$DOMAIN" ]]; then
        validation_errors+=("DOMAIN must be set to your actual domain in jstack.config")
    fi
    
    if [[ "$EMAIL" == "admin@example.com" ]] || [[ -z "$EMAIL" ]]; then
        validation_errors+=("EMAIL must be set to your actual email in jstack.config")
    fi
    
    # Check if ports are available
    local required_ports=(80 443)
    for port in "${required_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            validation_errors+=("Port $port is already in use")
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
    
    # Check if user has sudo access
    if ! sudo -n true 2>/dev/null; then
        prereq_errors+=("User does not have passwordless sudo access")
    fi
    
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