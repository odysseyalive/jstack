#!/bin/bash
# Centralized dependency installation for JarvisJR Stack on Debian 12
# This script installs ALL required dependencies before any JarvisJR operations

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 DEPENDENCY INSTALLATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Verify this is Debian 12
verify_debian_12() {
    log_info "Verifying Debian 12 compatibility"
    
    if [[ ! -f /etc/debian_version ]]; then
        log_error "This script is designed for Debian 12 only"
        return 1
    fi
    
    local debian_version
    debian_version=$(cat /etc/debian_version)
    
    if [[ ! "$debian_version" =~ ^12\. ]]; then
        log_warning "This script is optimized for Debian 12, detected version: $debian_version"
        log_info "Continuing installation but some packages may differ"
    else
        log_success "Debian 12 detected - proceeding with optimized installation"
    fi
}

# Update package repositories
update_package_repositories() {
    log_info "Updating package repositories"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would update package repositories"
        return 0
    fi
    
    execute_cmd "sudo apt-get update -y" "Update package lists"
    execute_cmd "sudo apt-get upgrade -y" "Upgrade existing packages"
    execute_cmd "sudo apt-get autoremove -y" "Remove unnecessary packages"
}

# Install critical dependencies first
install_critical_dependencies() {
    log_section "Installing Critical Dependencies"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install critical dependencies"
        return 0
    fi
    
    local critical_packages=(
        curl
        wget
        jq
        openssl
        tar
        gzip
        lsof
        systemd
        lsb-release
        ca-certificates
        apt-transport-https
        software-properties-common
        gnupg
        coreutils
    )
    
    log_info "Installing critical system dependencies"
    execute_cmd "sudo apt-get install -y ${critical_packages[*]}" "Install critical dependencies"
    
    # Verify critical tools are available
    local critical_commands=(curl wget jq openssl systemctl lsof)
    local missing_commands=()
    
    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Critical commands missing after installation: ${missing_commands[*]}"
        return 1
    fi
    
    log_success "All critical dependencies installed and verified"
}

# Add Docker repository and install Docker
install_docker_ecosystem() {
    log_section "Installing Docker Ecosystem"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install Docker ecosystem"
        return 0
    fi
    
    # Add Docker's official GPG key
    log_info "Adding Docker GPG key"
    execute_cmd "curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg" "Add Docker GPG key"
    
    # Add Docker repository
    log_info "Adding Docker repository"
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package list with Docker repository
    execute_cmd "sudo apt-get update -y" "Update package lists with Docker repository"
    
    # Install Docker components
    local docker_packages=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )
    
    log_info "Installing Docker components"
    execute_cmd "sudo apt-get install -y ${docker_packages[*]}" "Install Docker ecosystem"
    
    # Verify Docker installation
    if ! command -v docker &>/dev/null; then
        log_error "Docker installation failed"
        return 1
    fi
    
    log_success "Docker ecosystem installed successfully"
}

# Install web services
install_web_services() {
    log_section "Installing Web Services"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install web services"
        return 0
    fi
    
    local web_packages=(
        nginx
        certbot
        python3-certbot-nginx
    )
    
    log_info "Installing web server and SSL tools"
    execute_cmd "sudo apt-get install -y ${web_packages[*]}" "Install web services"
    
    log_success "Web services installed successfully"
}

# Install security tools
install_security_tools() {
    log_section "Installing Security Tools"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install security tools"
        return 0
    fi
    
    local security_packages=(
        ufw
        fail2ban
        apparmor
        apparmor-utils
        auditd
    )
    
    log_info "Installing security suite"
    execute_cmd "sudo apt-get install -y ${security_packages[*]}" "Install security tools"
    
    log_success "Security tools installed successfully"
}

# Install network and monitoring tools
install_network_monitoring() {
    log_section "Installing Network & Monitoring Tools"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install network and monitoring tools"
        return 0
    fi
    
    local network_packages=(
        sysstat
        net-tools
        iputils-ping
        netcat-openbsd
        dnsutils
        util-linux
        cron
    )
    
    log_info "Installing network and monitoring utilities"
    execute_cmd "sudo apt-get install -y ${network_packages[*]}" "Install network tools"
    
    log_success "Network and monitoring tools installed successfully"
}

# Install optional components (browser automation, development tools)
install_optional_components() {
    log_section "Installing Optional Components"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install optional components"
        return 0
    fi
    
    # Chrome for browser automation (if browser automation is enabled)
    if [[ "${ENABLE_BROWSER_AUTOMATION:-true}" == "true" ]]; then
        log_info "Installing Chrome for browser automation"
        
        # Add Google Chrome repository
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 2>/dev/null || true
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
        
        execute_cmd "sudo apt-get update -y" "Update with Chrome repository"
        execute_cmd "sudo apt-get install -y google-chrome-stable" "Install Chrome browser"
        
        # Install fonts for proper rendering
        local font_packages=(
            fonts-noto
            fonts-noto-color-emoji
            fonts-dejavu-core
        )
        
        execute_cmd "sudo apt-get install -y ${font_packages[*]}" "Install browser fonts"
        log_success "Browser automation components installed"
    fi
    
    # Development tools (optional)
    local dev_packages=(
        git
        nodejs
        npm
        python3-pip
    )
    
    log_info "Installing development tools (optional)"
    execute_cmd "sudo apt-get install -y ${dev_packages[*]} || true" "Install development tools"
    
    # Email tools (optional)
    log_info "Installing email tools (optional)"
    execute_cmd "sudo apt-get install -y mailutils sendmail || true" "Install email tools"
    
    log_success "Optional components installation completed"
}

# Install security monitoring tools (optional)
install_security_monitoring() {
    log_section "Installing Security Monitoring Tools (Optional)"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install security monitoring tools"
        return 0
    fi
    
    local security_monitoring_packages=(
        nmap
        lynis
        chkrootkit
        rkhunter
    )
    
    log_info "Installing security monitoring suite"
    execute_cmd "sudo apt-get install -y ${security_monitoring_packages[*]} || true" "Install security monitoring tools"
    
    log_success "Security monitoring tools installation completed"
}

# Verify all critical dependencies
verify_installation() {
    log_section "Verifying Installation"
    
    # Critical commands that must be available
    local critical_commands=(
        curl
        wget
        jq
        openssl
        docker
        systemctl
        nginx
        certbot
        ufw
        fail2ban
    )
    
    local missing_commands=()
    local available_commands=()
    
    for cmd in "${critical_commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            available_commands+=("$cmd")
        else
            missing_commands+=("$cmd")
        fi
    done
    
    # Report results
    log_info "Dependency verification results:"
    log_success "Available commands (${#available_commands[@]}): ${available_commands[*]}"
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing critical commands (${#missing_commands[@]}): ${missing_commands[*]}"
        log_error "JarvisJR Stack installation may fail without these dependencies"
        return 1
    fi
    
    log_success "All critical dependencies verified successfully"
    log_info "JarvisJR Stack is ready for installation"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN INSTALLATION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    log_section "JarvisJR Stack - Complete Dependency Installation"
    log_info "Installing all required dependencies for Debian 12"
    
    # Verify environment
    verify_debian_12 || exit 1
    
    # Installation phases
    update_package_repositories || exit 1
    install_critical_dependencies || exit 1
    install_docker_ecosystem || exit 1
    install_web_services || exit 1
    install_security_tools || exit 1
    install_network_monitoring || exit 1
    install_optional_components
    install_security_monitoring
    
    # Final verification
    verify_installation || exit 1
    
    log_success "Complete dependency installation finished successfully"
    log_info "You can now run './jstack.sh --install' to deploy JarvisJR Stack"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi