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
        "nginx:Web server"
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
        if command -v "$cmd" &>/dev/null; then
            log_success "✓ $cmd ($description)"
        else
            critical_missing+=("$cmd")
            log_error "✗ $cmd ($description) - CRITICAL"
        fi
    done
    
    log_info "Checking optional dependencies..."
    for dep_def in "${optional_deps[@]}"; do
        IFS=':' read -r cmd description <<< "$dep_def"
        if command -v "$cmd" &>/dev/null; then
            log_success "✓ $cmd ($description)"
        else
            optional_missing+=("$cmd")
            log_warning "⚠ $cmd ($description) - OPTIONAL"
        fi
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
    
    # Check Docker Compose
    if docker compose version &>/dev/null; then
        log_success "Docker Compose (plugin) available"
    elif command -v docker-compose &>/dev/null; then
        log_success "Docker Compose (standalone) available"
    else
        log_error "Docker Compose not available"
        return 1
    fi
    
    return 0
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
        log_info "3. Manual installation (see DEPENDENCY_MANIFEST.md)"
        log_info ""
        log_info "4. Force installation (not recommended):"
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
        *)
            echo "JarvisJR Stack Pre-Installation Check"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  check, validate    Run complete pre-installation check"
            echo "  dependencies, deps Check dependency availability"
            echo "  docker            Check Docker installation"
            echo ""
            echo "Examples:"
            echo "  $0 check          # Complete validation"
            echo "  $0 dependencies   # Check dependencies only"
            echo "  $0 docker         # Check Docker only"
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi