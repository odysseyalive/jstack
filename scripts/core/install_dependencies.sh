#!/bin/bash
# Quick Dependencies Installer for JarvisJR Stack
# Installs all required dependencies before main installation

set -e

# Get script directory and set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Source common utilities if available, otherwise use basic logging
if [[ -f "${PROJECT_ROOT}/scripts/lib/common.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/lib/common.sh"
else
    # Basic logging functions for bootstrap
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_error() { echo "[ERROR] $1"; }
    log_warning() { echo "[WARNING] $1"; }
    execute_cmd() { 
        local cmd="$1"
        local desc="$2"
        echo "[EXECUTING] $desc"
        eval "$cmd"
    }
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 QUICK DEPENDENCY INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════════

# Detect operating system
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        echo "debian"
    elif [[ -f /etc/redhat-release ]]; then
        echo "redhat" 
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# Install essential dependencies for Debian/Ubuntu
install_debian_essentials() {
    log_info "Installing essential dependencies for Debian/Ubuntu"
    
    # Update package lists
    execute_cmd "sudo apt-get update -y" "Update package lists"
    
    # Install absolute essentials first
    execute_cmd "sudo apt-get install -y curl wget jq openssl" "Install core utilities"
    
    # Install Docker if not present
    if ! command -v docker &>/dev/null; then
        log_info "Installing Docker"
        execute_cmd "curl -fsSL https://get.docker.com | sh" "Install Docker"
        execute_cmd "sudo systemctl enable docker" "Enable Docker service"
        execute_cmd "sudo systemctl start docker" "Start Docker service"
    else
        log_info "Docker already installed"
    fi
    
    # Install system essentials
    execute_cmd "sudo apt-get install -y \
        tar gzip nginx certbot python3-certbot-nginx \
        ufw fail2ban lsb-release ca-certificates \
        apt-transport-https software-properties-common gnupg \
        lsof sysstat net-tools iputils-ping netcat-openbsd dnsutils" \
        "Install system essentials"
    
    # Install security tools
    execute_cmd "sudo apt-get install -y apparmor apparmor-utils auditd" "Install security tools"
    
    log_success "Essential dependencies installed for Debian/Ubuntu"
}

# Install essential dependencies for RHEL/CentOS
install_redhat_essentials() {
    log_info "Installing essential dependencies for RHEL/CentOS"
    
    # Install EPEL if available
    if command -v yum &>/dev/null; then
        execute_cmd "sudo yum install -y epel-release || true" "Install EPEL repository"
        execute_cmd "sudo yum update -y" "Update package lists"
        local pkg_manager="yum"
    elif command -v dnf &>/dev/null; then
        execute_cmd "sudo dnf update -y" "Update package lists"
        local pkg_manager="dnf"
    else
        log_error "No package manager found (yum/dnf)"
        return 1
    fi
    
    # Install essentials
    execute_cmd "sudo $pkg_manager install -y curl wget jq openssl tar gzip" "Install core utilities"
    
    # Install Docker if not present
    if ! command -v docker &>/dev/null; then
        log_info "Installing Docker"
        execute_cmd "curl -fsSL https://get.docker.com | sh" "Install Docker"
        execute_cmd "sudo systemctl enable docker" "Enable Docker service"
        execute_cmd "sudo systemctl start docker" "Start Docker service"
    else
        log_info "Docker already installed"
    fi
    
    # Install system essentials
    execute_cmd "sudo $pkg_manager install -y \
        nginx certbot python3-certbot-nginx \
        firewalld fail2ban audit \
        lsof bind-utils net-tools iputils" \
        "Install system essentials"
    
    log_success "Essential dependencies installed for RHEL/CentOS"
}

# Install essential dependencies for Arch Linux
install_arch_essentials() {
    log_info "Installing essential dependencies for Arch Linux"
    
    # Update package database
    execute_cmd "sudo pacman -Sy" "Update package database"
    
    # Install essentials
    execute_cmd "sudo pacman -S --noconfirm curl wget jq openssl tar gzip" "Install core utilities"
    
    # Install Docker if not present
    if ! command -v docker &>/dev/null; then
        log_info "Installing Docker"
        execute_cmd "sudo pacman -S --noconfirm docker docker-compose" "Install Docker"
        execute_cmd "sudo systemctl enable docker" "Enable Docker service"
        execute_cmd "sudo systemctl start docker" "Start Docker service"
    else
        log_info "Docker already installed"
    fi
    
    # Install system essentials
    execute_cmd "sudo pacman -S --noconfirm \
        nginx certbot ufw fail2ban apparmor audit \
        lsof bind-tools net-tools iputils \
        noto-fonts noto-fonts-emoji ttf-dejavu" \
        "Install system essentials"
    
    log_success "Essential dependencies installed for Arch Linux"
}

# Main installation function
install_dependencies() {
    local os_type
    os_type=$(detect_os)
    
    log_info "Detected operating system: $os_type"
    
    case "$os_type" in
        "debian")
            install_debian_essentials
            ;;
        "redhat")
            install_redhat_essentials
            ;;
        "arch")
            install_arch_essentials
            ;;
        *)
            log_error "Unsupported operating system: $os_type"
            log_info "Supported systems: Debian/Ubuntu, RHEL/CentOS/Fedora, Arch Linux"
            return 1
            ;;
    esac
    
    # Validate installation
    log_info "Validating critical dependencies"
    local critical_deps=("curl" "wget" "jq" "openssl" "docker" "nginx" "ufw")
    local missing_deps=()
    
    for dep in "${critical_deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            log_success "✓ $dep"
        else
            missing_deps+=("$dep")
            log_error "✗ $dep"
        fi
    done
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        log_success "All critical dependencies installed successfully"
        return 0
    else
        log_error "Installation incomplete - missing: ${missing_deps[*]}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    case "${1:-install}" in
        "install"|"setup")
            echo "JarvisJR Stack - Dependency Installer"
            echo "====================================="
            echo ""
            install_dependencies
            echo ""
            log_success "Dependency installation complete!"
            log_info "You can now run the main JarvisJR Stack installation:"
            log_info "  ./jstack.sh"
            ;;
        "check"|"validate")
            echo "JarvisJR Stack - Dependency Validation"
            echo "======================================"
            echo ""
            if [[ -f "${PROJECT_ROOT}/scripts/core/dependency_management.sh" ]]; then
                bash "${PROJECT_ROOT}/scripts/core/dependency_management.sh" validate
            else
                log_error "Dependency management script not found"
                log_info "Run: $0 install"
            fi
            ;;
        *)
            echo "JarvisJR Stack - Quick Dependency Installer"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  install, setup    Install all essential dependencies"
            echo "  check, validate   Validate dependency installation"
            echo ""
            echo "Examples:"
            echo "  $0 install       # Install dependencies"
            echo "  $0 check         # Validate installation"
            echo ""
            echo "Supported Platforms:"
            echo "  - Debian/Ubuntu (apt)"
            echo "  - RHEL/CentOS/Fedora (yum/dnf)"
            echo "  - Arch Linux (pacman)"
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi