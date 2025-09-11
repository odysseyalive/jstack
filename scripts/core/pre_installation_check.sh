#!/bin/bash
# Pre-Installation Dependency Check for JarvisJR Stack
# Validates all dependencies before starting main installation

set -e # Exit on any error

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 PRE-INSTALLATION VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Check critical dependencies before installation
# Detect package manager for proper package validation
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

check_critical_dependencies() {
    log_section "Pre-Installation Dependency Check"
    
    local critical_missing=()
    local optional_missing=()
    
    # Critical dependencies (installation will fail without these)
    local critical_deps=(
        "bash:Shell interpreter"
        "sudo:Superuser access"
        "curl:HTTP client for downloads"
        "wget:File downloader"
        "jq:JSON processor for configuration"
        "openssl:SSL and encryption toolkit"
        "systemctl:Service management"
        "docker:Container runtime"
        "certbot:SSL certificate management"
        "ufw:Firewall management"
    )
    
    # Optional dependencies (installation can proceed without these)
    local optional_deps=(
        "fail2ban:Intrusion prevention"
        "apparmor:Security framework"
        "auditd:Security auditing"
        "git:Version control"
        "lsof:Process monitoring"
        "dig:DNS lookup"
        "netstat:Network statistics"
    )
    
    log_info "Checking critical dependencies..."
    for dep_def in "${critical_deps[@]}"; do
        IFS=':' read -r cmd description <<< "$dep_def"
        
        # Check system packages that require sudo to detect properly
        case "$cmd" in
            "ufw"|"certbot")
                # Check if package is installed using package manager
                local package_manager=$(detect_package_manager)
                case "$package_manager" in
                    "apt")
                        if sudo dpkg -l "$cmd" 2>/dev/null | grep -q "^ii"; then
                            log_success "✓ $cmd ($description)"
                        else
                            critical_missing+=("$cmd")
                            log_error "✗ $cmd ($description) - CRITICAL"
                        fi
                        ;;
                    "yum"|"dnf")
                        if sudo rpm -q "$cmd" &>/dev/null; then
                            log_success "✓ $cmd ($description)"
                        else
                            critical_missing+=("$cmd")
                            log_error "✗ $cmd ($description) - CRITICAL"
                        fi
                        ;;
                    "pacman")
                        if sudo pacman -Q "$cmd" &>/dev/null; then
                            log_success "✓ $cmd ($description)"
                        else
                            critical_missing+=("$cmd")
                            log_error "✗ $cmd ($description) - CRITICAL"
                        fi
                        ;;
                    *)
                        # Fallback to command check for unknown package managers
                        if command -v "$cmd" &>/dev/null; then
                            log_success "✓ $cmd ($description)"
                        else
                            critical_missing+=("$cmd")
                            log_error "✗ $cmd ($description) - CRITICAL"
                        fi
                        ;;
                esac
                ;;
            *)
                # Standard command availability check for other tools
                if command -v "$cmd" &>/dev/null; then
                    log_success "✓ $cmd ($description)"
                else
                    critical_missing+=("$cmd")
                    log_error "✗ $cmd ($description) - CRITICAL"
                fi
                ;;
        esac
    done
    
    log_info "Checking optional dependencies..."
    for dep_def in "${optional_deps[@]}"; do
        IFS=':' read -r cmd description <<< "$dep_def"
        
        # Check system packages that require sudo to detect properly
        case "$cmd" in
            "fail2ban"|"apparmor"|"auditd")
                # Check if package is installed using package manager
                local package_manager=$(detect_package_manager)
                case "$package_manager" in
                    "apt")
                        if sudo dpkg -l "$cmd" 2>/dev/null | grep -q "^ii"; then
                            log_success "✓ $cmd ($description)"
                        else
                            optional_missing+=("$cmd")
                            log_warning "⚠ $cmd ($description) - OPTIONAL"
                        fi
                        ;;
                    "yum"|"dnf")
                        if sudo rpm -q "$cmd" &>/dev/null; then
                            log_success "✓ $cmd ($description)"
                        else
                            optional_missing+=("$cmd")
                            log_warning "⚠ $cmd ($description) - OPTIONAL"
                        fi
                        ;;
                    "pacman")
                        if sudo pacman -Q "$cmd" &>/dev/null; then
                            log_success "✓ $cmd ($description)"
                        else
                            optional_missing+=("$cmd")
                            log_warning "⚠ $cmd ($description) - OPTIONAL"
                        fi
                        ;;
                    *)
                        # Fallback to command check for unknown package managers
                        if command -v "$cmd" &>/dev/null; then
                            log_success "✓ $cmd ($description)"
                        else
                            optional_missing+=("$cmd")
                            log_warning "⚠ $cmd ($description) - OPTIONAL"
                        fi
                        ;;
                esac
                ;;
            *)
                # Standard command availability check for other tools
                if command -v "$cmd" &>/dev/null; then
                    log_success "✓ $cmd ($description)"
                else
                    optional_missing+=("$cmd")
                    log_warning "⚠ $cmd ($description) - OPTIONAL"
                fi
                ;;
        esac
    done
    
    # Report results
    echo ""
    if [[ ${#critical_missing[@]} -eq 0 ]]; then
        log_success "All critical dependencies are available"
        if [[ ${#optional_missing[@]} -gt 0 ]]; then
            log_info "Optional dependencies missing: ${optional_missing[*]}"
            log_info "Installation can proceed, but some features may be limited"
        fi
        return 0
    else
        log_error "Critical dependencies missing: ${critical_missing[*]}"
        log_error "Installation cannot proceed without these dependencies"
        
        echo ""
        log_info "To install missing dependencies:"
        log_info "  Option 1: ./scripts/core/install_dependencies.sh"
        log_info "  Option 2: ./scripts/core/dependency_management.sh install"
        log_info "  Option 3: Manual installation using package manager"
        
        return 1
    fi
}

# Validate Docker specifically (critical for JarvisJR)
check_docker_availability() {
    log_info "Validating Docker installation"
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker not found - required for JarvisJR Stack"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        log_warning "Docker daemon not running - attempting to start"
        if systemctl is-active docker &>/dev/null; then
            log_info "Docker service is active but daemon not responding"
        else
            log_info "Starting Docker service"
            if sudo systemctl start docker; then
                sleep 3
                if docker info &>/dev/null; then
                    log_success "Docker daemon started successfully"
                else
                    log_error "Docker daemon failed to start properly"
                    return 1
                fi
            else
                log_error "Failed to start Docker service"
                return 1
            fi
        fi
    else
        log_success "Docker daemon is running"
    fi
    
    # Check Docker Compose with improved compatibility detection
    local docker_compose_available=false
    
    # Check for docker compose plugin (modern approach)
    if docker compose version &> /dev/null; then
        docker_compose_available=true
        log_success "Docker Compose plugin available"
    # Check for standalone docker-compose command (legacy approach)  
    elif command -v docker-compose &> /dev/null && docker-compose version &> /dev/null; then
        docker_compose_available=true
        log_success "Docker Compose standalone available"
    # Check for docker-compose plugin via docker CLI
    elif docker --help 2>/dev/null | grep -q "compose"; then
        docker_compose_available=true
        log_success "Docker Compose plugin available via docker CLI"
    fi
    
    if [[ "$docker_compose_available" == "false" ]]; then
        log_error "Docker Compose not available"
        log_info "Install options: docker-compose-plugin, docker-compose, or Docker Desktop"
        return 1
    fi
    
    return 0
}

# Check for nginx conflicts (system nginx vs containerized nginx)
check_nginx_conflicts() {
    log_info "Checking for nginx conflicts"
    
    local nginx_conflicts_detected=false
    local package_manager=$(detect_package_manager)
    
    # Check if system nginx package is installed
    local nginx_package_installed=false
    case "$package_manager" in
        "apt")
            if sudo dpkg -l nginx nginx-common nginx-core 2>/dev/null | grep -q "^ii"; then
                nginx_package_installed=true
            fi
            ;;
        "yum"|"dnf")
            if sudo rpm -q nginx 2>/dev/null | grep -q "nginx"; then
                nginx_package_installed=true
            fi
            ;;
        "pacman")
            if sudo pacman -Q nginx 2>/dev/null | grep -q "nginx"; then
                nginx_package_installed=true
            fi
            ;;
        *)
            log_warning "Unknown package manager - using command check for nginx"
            if command -v nginx &>/dev/null; then
                nginx_package_installed=true
            fi
            ;;
    esac
    
    # Check for running nginx processes
    local nginx_processes_running=false
    if pgrep -x nginx >/dev/null 2>&1; then
        nginx_processes_running=true
    fi
    
    # Check if nginx service is enabled/active
    local nginx_service_active=false
    if systemctl is-active nginx >/dev/null 2>&1 || systemctl is-enabled nginx >/dev/null 2>&1; then
        nginx_service_active=true
    fi
    
    # Check if ports 80/443 are in use by nginx
    local nginx_ports_occupied=false
    if command -v lsof >/dev/null 2>&1; then
        if sudo lsof -i :80 2>/dev/null | grep -q nginx || sudo lsof -i :443 2>/dev/null | grep -q nginx; then
            nginx_ports_occupied=true
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tulpn 2>/dev/null | grep -E ":80|:443" | grep -q nginx; then
            nginx_ports_occupied=true
        fi
    fi
    
    # Report conflicts
    if $nginx_package_installed || $nginx_processes_running || $nginx_service_active || $nginx_ports_occupied; then
        log_warning "Nginx conflicts detected:"
        
        if $nginx_package_installed; then
            log_warning "  ⚠ System nginx package is installed"
            nginx_conflicts_detected=true
        fi
        
        if $nginx_processes_running; then
            log_warning "  ⚠ Nginx processes are currently running"
            nginx_conflicts_detected=true
        fi
        
        if $nginx_service_active; then
            log_warning "  ⚠ Nginx service is active/enabled"
            nginx_conflicts_detected=true
        fi
        
        if $nginx_ports_occupied; then
            log_warning "  ⚠ Nginx is occupying ports 80/443"
            nginx_conflicts_detected=true
        fi
        
        echo ""
        log_warning "JarvisJR Stack uses containerized nginx, which conflicts with system nginx"
        log_info "System nginx must be removed to avoid port conflicts (80/443)"
        log_info "Container nginx will provide all web server functionality"
        echo ""
        log_info "Conflict resolution options:"
        log_info "  1. Automatic removal: ./jstack.sh --resolve-nginx-conflicts"
        log_info "  2. Manual removal: ./scripts/core/pre_installation_check.sh remove-nginx"
        log_info "  3. Force installation: ./jstack.sh --force-install (not recommended)"
        
        return 1
    else
        log_success "No nginx conflicts detected"
        log_info "System is ready for containerized nginx deployment"
        return 0
    fi
}

# Remove conflicting system nginx installation
remove_conflicting_nginx() {
    log_section "Removing Conflicting System Nginx"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would remove conflicting system nginx installation"
        return 0
    fi
    
    local package_manager=$(detect_package_manager)
    local removal_failed=false
    
    # Stop nginx service first
    log_info "Stopping nginx service if running"
    if systemctl is-active nginx >/dev/null 2>&1; then
        if sudo systemctl stop nginx; then
            log_success "Stopped nginx service"
        else
            log_warning "Failed to stop nginx service (continuing anyway)"
        fi
    fi
    
    # Disable nginx service
    if systemctl is-enabled nginx >/dev/null 2>&1; then
        if sudo systemctl disable nginx; then
            log_success "Disabled nginx service"
        else
            log_warning "Failed to disable nginx service (continuing anyway)"
        fi
    fi
    
    # Remove nginx packages based on package manager
    log_info "Removing nginx packages using $package_manager package manager"
    case "$package_manager" in
        "apt")
            # Remove nginx packages and dependencies
            local packages_to_remove=(
                "nginx" "nginx-common" "nginx-core" "nginx-full" 
                "nginx-light" "nginx-extras" "nginx-doc"
            )
            
            for package in "${packages_to_remove[@]}"; do
                if sudo dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
                    log_info "Removing package: $package"
                    if sudo apt-get remove --purge -y "$package" 2>/dev/null; then
                        log_success "Removed $package"
                    else
                        log_warning "Failed to remove $package (may not be critical)"
                    fi
                fi
            done
            
            # Clean up any remaining configuration
            if sudo apt-get autoremove -y 2>/dev/null; then
                log_success "Cleaned up unused dependencies"
            fi
            ;;
            
        "yum")
            if sudo yum remove -y nginx 2>/dev/null; then
                log_success "Removed nginx package"
            else
                log_error "Failed to remove nginx using yum"
                removal_failed=true
            fi
            ;;
            
        "dnf")
            if sudo dnf remove -y nginx 2>/dev/null; then
                log_success "Removed nginx package"
            else
                log_error "Failed to remove nginx using dnf"
                removal_failed=true
            fi
            ;;
            
        "pacman")
            if sudo pacman -R --noconfirm nginx 2>/dev/null; then
                log_success "Removed nginx package"
            else
                log_error "Failed to remove nginx using pacman"
                removal_failed=true
            fi
            ;;
            
        *)
            log_error "Unknown package manager: $package_manager"
            log_error "Manual nginx removal required"
            removal_failed=true
            ;;
    esac
    
    # Clean up configuration directories
    log_info "Cleaning up nginx configuration directories"
    local config_dirs=(
        "/etc/nginx"
        "/var/log/nginx"
        "/var/cache/nginx"
        "/var/lib/nginx"
    )
    
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Removing directory: $dir"
            if sudo rm -rf "$dir" 2>/dev/null; then
                log_success "Removed $dir"
            else
                log_warning "Could not remove $dir (may require manual cleanup)"
            fi
        fi
    done
    
    # Verify removal success
    sleep 2
    if ! check_nginx_conflicts >/dev/null 2>&1; then
        log_success "System nginx successfully removed"
        log_info "JarvisJR Stack can now deploy containerized nginx without conflicts"
        return 0
    else
        log_error "Nginx conflict removal incomplete"
        if $removal_failed; then
            log_error "Package removal failed - manual intervention required"
            log_info ""
            log_info "Manual removal steps:"
            log_info "  1. Stop nginx: sudo systemctl stop nginx"
            log_info "  2. Disable nginx: sudo systemctl disable nginx"
            log_info "  3. Remove packages: sudo $package_manager remove nginx"
            log_info "  4. Clean config: sudo rm -rf /etc/nginx"
        fi
        return 1
    fi
}

# Main pre-installation check
run_pre_installation_check() {
    log_section "JarvisJR Stack Pre-Installation Validation"
    
    local check_failed=false
    
    # Check critical dependencies
    if ! check_critical_dependencies; then
        check_failed=true
    fi
    
    echo ""
    
    # Check Docker specifically
    if ! check_docker_availability; then
        check_failed=true
    fi
    
    echo ""
    
    # Check for nginx conflicts
    if ! check_nginx_conflicts; then
        check_failed=true
    fi
    
    echo ""
    
    # Final result
    if $check_failed; then
        log_error "Pre-installation check failed"
        log_info ""
        log_info "REMEDIATION OPTIONS:"
        log_info "==================="
        log_info ""
        log_info "1. Auto-install dependencies:"
        log_info "   ./scripts/core/install_dependencies.sh"
        log_info ""
        log_info "2. Comprehensive dependency management:"
        log_info "   ./scripts/core/dependency_management.sh install"
        log_info ""
        log_info "3. Resolve nginx conflicts:"
        log_info "   ./scripts/core/pre_installation_check.sh remove-nginx"
        log_info ""
        log_info "4. Manual installation (see DEPENDENCY_MANIFEST.md)"
        log_info ""
        log_info "5. Force installation (not recommended):"
        log_info "   ./jstack.sh --force-install"
        log_info ""
        return 1
    else
        log_success "Pre-installation check passed"
        log_info "All required dependencies are available"
        log_info "JarvisJR Stack installation can proceed"
        return 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    case "${1:-check}" in
        "check"|"validate")
            run_pre_installation_check
            ;;
        "dependencies"|"deps")
            check_critical_dependencies
            ;;
        "docker")
            check_docker_availability
            ;;
        "nginx-conflicts"|"nginx")
            check_nginx_conflicts
            ;;
        "remove-nginx"|"fix-nginx")
            remove_conflicting_nginx
            ;;
        *)
            echo "JarvisJR Stack Pre-Installation Check"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  check, validate       Run complete pre-installation check"
            echo "  dependencies, deps    Check dependency availability"
            echo "  docker               Check Docker installation"
            echo "  nginx-conflicts      Check for nginx conflicts only"
            echo "  remove-nginx         Remove conflicting system nginx"
            echo ""
            echo "Examples:"
            echo "  $0 check             # Complete validation"
            echo "  $0 dependencies      # Check dependencies only"
            echo "  $0 docker            # Check Docker only"
            echo "  $0 nginx-conflicts   # Check nginx conflicts only"
            echo "  $0 remove-nginx      # Remove system nginx"
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi