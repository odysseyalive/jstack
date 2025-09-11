#!/bin/bash
# JarvisJR Stack Dependency Management System
# Comprehensive dependency validation and installation for all JarvisJR components

set -e # Exit on any error

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 📋 DEPENDENCY CATALOG
# ═══════════════════════════════════════════════════════════════════════════════

# Core System Tools (Essential - Required on all systems)
declare -A CORE_SYSTEM_TOOLS=(
    ["bash"]="Shell interpreter|shells|4.0+|All scripts execution"
    ["sudo"]="Superuser access|sudo|1.8+|Privileged operations"
    ["systemctl"]="Systemd service control|systemd|220+|Service management"
    ["crontab"]="Task scheduler|cron|3.0+|Automated tasks"
    ["mkdir"]="Directory creation|coreutils|8.0+|Directory operations"
    ["chown"]="Ownership change|coreutils|8.0+|File permissions"
    ["chmod"]="Permission change|coreutils|8.0+|File permissions"
    ["mv"]="File movement|coreutils|8.0+|File operations"
    ["cp"]="File copying|coreutils|8.0+|File operations"
    ["rm"]="File removal|coreutils|8.0+|File operations"
    ["find"]="File search|findutils|4.6+|File discovery"
    ["xargs"]="Command execution|findutils|4.6+|Batch operations"
    ["sort"]="Text sorting|coreutils|8.0+|Data processing"
    ["head"]="Text head extraction|coreutils|8.0+|Log processing"
    ["tail"]="Text tail extraction|coreutils|8.0+|Log monitoring"
    ["cut"]="Text field extraction|coreutils|8.0+|Data parsing"
    ["tr"]="Text transformation|coreutils|8.0+|Data processing"
    ["sed"]="Stream editing|sed|4.2+|Text processing"
    ["awk"]="Pattern scanning|gawk|4.1+|Data processing"
    ["grep"]="Pattern matching|grep|3.1+|Text search"
    ["wc"]="Word/line counting|coreutils|8.0+|Data analysis"
)

# Network Utilities (Critical - Required for connectivity and SSL)
declare -A NETWORK_TOOLS=(
    ["curl"]="HTTP client|curl|7.58+|Downloads, API calls, IP detection"
    ["wget"]="File downloader|wget|1.19+|Package downloads"
    ["dig"]="DNS lookup|dnsutils|9.11+|Domain validation"
    ["nslookup"]="DNS query|dnsutils|9.11+|Domain resolution fallback"
    ["ping"]="Network connectivity|iputils-ping|3.0+|Network testing"
    ["nc"]="Network connections|netcat-openbsd|1.190+|Port testing"
    ["netstat"]="Network statistics|net-tools|1.60+|Network diagnostics"
    ["ss"]="Socket statistics|iproute2|4.15+|Network monitoring"
    ["lsof"]="Open files listing|lsof|4.89+|Process diagnostics"
    ["nginx"]="Web server|nginx|1.18+|Reverse proxy"
)

# JSON and Data Processing (Critical - Required for configuration)
declare -A DATA_PROCESSING_TOOLS=(
    ["jq"]="JSON processor|jq|1.5+|Configuration parsing, API responses"
    ["base64"]="Base64 encoding|coreutils|8.0+|Secret generation"
    ["openssl"]="Cryptography toolkit|openssl|1.1.1+|SSL, encryption, secrets"
    ["tar"]="Archive utility|tar|1.30+|Backup creation"
    ["gzip"]="Compression utility|gzip|1.6+|Backup compression"
    ["gunzip"]="Decompression utility|gzip|1.6+|Backup extraction"
)

# Docker Ecosystem (Critical - Core platform requirement)
declare -A DOCKER_TOOLS=(
    ["docker"]="Container runtime|docker-ce|20.10+|Container management"
    ["docker-compose"]="Multi-container orchestration|docker-compose-plugin|2.0+|Service orchestration"
)

# System Information and Monitoring (Required - System management)
declare -A SYSTEM_MONITORING=(
    ["ps"]="Process listing|procps|3.3+|Process monitoring"
    ["free"]="Memory information|procps|3.3+|Memory diagnostics"
    ["df"]="Disk usage|coreutils|8.0+|Storage monitoring"
    ["du"]="Directory usage|coreutils|8.0+|Space analysis"
    ["lsb_release"]="Distribution info|lsb-release|9.0+|OS identification"
    ["timedatectl"]="Time/timezone control|systemd|220+|Timezone configuration"
    ["loginctl"]="Login management|systemd|220+|User session control"
    ["uname"]="System information|coreutils|8.0+|System diagnostics"
    ["hostname"]="System hostname|hostname|3.13+|System identification"
    ["uptime"]="System uptime|procps|3.3+|System diagnostics"
    ["whoami"]="Current user|coreutils|8.0+|User identification"
    ["id"]="User/group info|coreutils|8.0+|Permission validation"
    ["groups"]="Group membership|coreutils|8.0+|Group validation"
    ["getent"]="Name service lookup|libc-bin|2.27+|User/group queries"
)

# User and Permission Management (Required - Security)
declare -A USER_MANAGEMENT=(
    ["useradd"]="User creation|passwd|1.5+|Service user setup"
    ["usermod"]="User modification|passwd|1.5+|Group membership"
    ["groupadd"]="Group creation|passwd|1.5+|Group management"
)

# Web Services (Critical - Web server and SSL)
declare -A WEB_SERVICES=(
    ["certbot"]="SSL certificates|certbot|1.21+|Let's Encrypt automation"
)

# Firewall and Security (Required - Security hardening)
declare -A SECURITY_TOOLS=(
    ["ufw"]="Firewall management|ufw|0.36+|Firewall configuration"
    ["fail2ban"]="Intrusion prevention|fail2ban|0.11+|Security monitoring"
    ["fail2ban-client"]="Fail2ban control|fail2ban|0.11+|Security management"
    ["apparmor"]="Security framework|apparmor|2.13+|Container security"
    ["apparmor-utils"]="AppArmor utilities|apparmor-utils|2.13+|Security profile management"
    ["apparmor_parser"]="Profile parser|apparmor|2.13+|Security profile loading"
    ["auditd"]="Audit daemon|auditd|2.8+|Security auditing"
)

# Package Management (Platform-specific - Required for installation)
declare -A PACKAGE_MANAGERS=(
    ["apt-get"]="Package manager|apt|1.6+|Debian/Ubuntu package installation"
    ["apt"]="Package manager|apt|1.6+|Debian/Ubuntu package management"
    ["yum"]="Package manager|yum|3.4+|RHEL/CentOS package installation"
    ["dnf"]="Package manager|dnf|4.0+|Fedora package installation"
    ["pacman"]="Package manager|pacman|5.2+|Arch Linux package installation"
    ["snap"]="Universal packages|snapd|2.45+|Universal package installation"
)

# Development and Build Tools (Optional - Advanced features)
declare -A DEVELOPMENT_TOOLS=(
    ["git"]="Version control|git|2.17+|Repository management"
    ["npm"]="Node package manager|npm|6.14+|Node.js package management"
    ["pip"]="Python package manager|python3-pip|20.0+|Python package installation"
    ["python3"]="Python interpreter|python3|3.6+|Script execution"
    ["node"]="Node.js runtime|nodejs|14.0+|JavaScript execution"
)

# Monitoring and Analysis (Optional - Enhanced diagnostics)
declare -A MONITORING_TOOLS=(
    ["iostat"]="I/O statistics|sysstat|12.0+|Performance monitoring"
    ["nmap"]="Network scanner|nmap|7.70+|Security scanning"
    ["nikto"]="Web scanner|nikto|2.1+|Web security scanning"
    ["lynis"]="Security auditing|lynis|3.0+|System security audit"
    ["chkrootkit"]="Rootkit checker|chkrootkit|0.52+|Malware detection"
    ["rkhunter"]="Rootkit hunter|rkhunter|1.4+|Malware detection"
    ["clamav"]="Antivirus scanner|clamav|0.103+|Virus scanning"
    ["clamav-daemon"]="Antivirus daemon|clamav-daemon|0.103+|Background virus scanning"
    ["trivy"]="Container scanner|trivy|0.48+|Container vulnerability scanning"
    ["falco"]="Runtime security|falco|0.34+|Runtime threat detection"
)

# Text Processing and Fonts (Optional - Browser automation)
declare -A TEXT_PROCESSING=(
    ["fonts-noto"]="Noto fonts|fonts-noto|20200323+|International text rendering"
    ["fonts-noto-color-emoji"]="Emoji fonts|fonts-noto-color-emoji|2.034+|Emoji rendering"
    ["fonts-dejavu-core"]="DejaVu fonts|fonts-dejavu-core|2.37+|Text rendering"
    ["ttf-dejavu"]="DejaVu fonts (Arch)|ttf-dejavu|2.37+|Text rendering (Arch)"
    ["noto-fonts"]="Noto fonts (Arch)|noto-fonts|2023.01+|International text (Arch)"
    ["noto-fonts-emoji"]="Emoji fonts (Arch)|noto-fonts-emoji|2.042+|Emoji rendering (Arch)"
)

# Browser Dependencies (Optional - Browser automation)
declare -A BROWSER_TOOLS=(
    ["google-chrome"]="Chrome browser|google-chrome-stable|latest|Browser automation"
    ["chromium"]="Chromium browser|chromium-browser|latest|Browser automation fallback"
    ["google-chrome-stable"]="Chrome stable|google-chrome-stable|latest|Browser automation"
)

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 DEPENDENCY VALIDATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Check if a command exists
command_exists() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null
}

# Check package manager availability
detect_package_manager() {
    if command_exists apt-get; then
        echo "apt"
    elif command_exists yum; then
        echo "yum"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists pacman; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Validate dependency category
validate_dependency_category() {
    local category="$1"
    local -n deps_ref=$2
    local missing_deps=()
    local optional_missing=()
    
    log_info "Validating $category dependencies"
    
    for cmd in "${!deps_ref[@]}"; do
        if command_exists "$cmd"; then
            log_success "✓ $cmd"
        else
            IFS='|' read -r description package version usage <<< "${deps_ref[$cmd]}"
            
            # Categorize as critical vs optional based on category
            case "$category" in
                "Core System Tools"|"Network Tools"|"JSON and Data Processing"|"Docker Tools"|"Web Services"|"Security Tools")
                    missing_deps+=("$cmd")
                    log_error "✗ $cmd (CRITICAL - $description)"
                    ;;
                *)
                    optional_missing+=("$cmd")
                    log_warning "⚠ $cmd (OPTIONAL - $description)"
                    ;;
            esac
        fi
    done
    
    # Return status
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "$category validation failed: ${#missing_deps[@]} critical dependencies missing"
        return 1
    elif [[ ${#optional_missing[@]} -gt 0 ]]; then
        log_warning "$category validation passed with ${#optional_missing[@]} optional dependencies missing"
        return 0
    else
        log_success "$category validation passed completely"
        return 0
    fi
}

# Comprehensive dependency validation
validate_all_dependencies() {
    log_section "Comprehensive Dependency Validation"
    
    local validation_failed=false
    local categories=(
        "Core System Tools:CORE_SYSTEM_TOOLS"
        "Network Tools:NETWORK_TOOLS"
        "JSON and Data Processing:DATA_PROCESSING_TOOLS"
        "Docker Tools:DOCKER_TOOLS"
        "System Monitoring:SYSTEM_MONITORING"
        "User Management:USER_MANAGEMENT"
        "Web Services:WEB_SERVICES"
        "Security Tools:SECURITY_TOOLS"
        "Package Managers:PACKAGE_MANAGERS"
        "Development Tools:DEVELOPMENT_TOOLS"
        "Monitoring Tools:MONITORING_TOOLS"
        "Text Processing:TEXT_PROCESSING"
        "Browser Tools:BROWSER_TOOLS"
    )
    
    for category_def in "${categories[@]}"; do
        IFS=':' read -r category_name category_var <<< "$category_def"
        local -n category_deps=$category_var
        
        if ! validate_dependency_category "$category_name" category_deps; then
            case "$category_name" in
                "Core System Tools"|"Network Tools"|"JSON and Data Processing"|"Docker Tools"|"Web Services"|"Security Tools")
                    validation_failed=true
                    ;;
            esac
        fi
        echo ""
    done
    
    if $validation_failed; then
        log_error "Dependency validation failed - critical dependencies missing"
        return 1
    else
        log_success "Dependency validation passed - all critical dependencies available"
        return 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📦 DEPENDENCY INSTALLATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Install dependencies for Debian/Ubuntu systems
install_dependencies_apt() {
    log_info "Installing dependencies using apt package manager"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would update package lists and install dependencies"
        return 0
    fi
    
    # Update package lists
    execute_cmd "sudo apt-get update -y" "Update package lists"
    
    # Essential packages (always install)
    local essential_packages=(
        "curl" "wget" "jq" "openssl" "tar" "gzip"
        "docker-ce" "docker-ce-cli" "containerd.io" 
        "docker-buildx-plugin" "docker-compose-plugin"
        "nginx" "certbot" "python3-certbot-nginx"
        "ufw" "fail2ban" "apparmor" "apparmor-utils" "auditd"
        "lsb-release" "ca-certificates" "apt-transport-https" 
        "software-properties-common" "gnupg" "lsof"
    )
    
    execute_cmd "sudo apt-get install -y ${essential_packages[*]}" "Install essential packages"
    
    # Optional monitoring packages
    local monitoring_packages=(
        "sysstat" "net-tools" "iputils-ping" "netcat-openbsd"
        "dnsutils" "nmap" "lynis" "chkrootkit" "rkhunter"
    )
    
    execute_cmd "sudo apt-get install -y ${monitoring_packages[*]} || true" "Install monitoring packages (optional)"
    
    # Browser dependencies (optional)
    local browser_packages=(
        "fonts-noto" "fonts-noto-color-emoji" "fonts-dejavu-core"
        "libnss3" "libatk-bridge2.0-0" "libdrm2" "libxkbcommon0"
        "libxcomposite1" "libxdamage1" "libxrandr2" "libgbm1"
        "libxss1" "libasound2"
    )
    
    execute_cmd "sudo apt-get install -y ${browser_packages[*]} || true" "Install browser dependencies (optional)"
}

# Install dependencies for RHEL/CentOS systems
install_dependencies_yum() {
    log_info "Installing dependencies using yum package manager"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install dependencies using yum"
        return 0
    fi
    
    # Essential packages
    local essential_packages=(
        "curl" "wget" "jq" "openssl" "tar" "gzip"
        "nginx" "certbot" "python3-certbot-nginx"
        "firewalld" "fail2ban" "audit"
        "lsof" "bind-utils" "net-tools" "iputils"
    )
    
    execute_cmd "sudo yum install -y ${essential_packages[*]}" "Install essential packages"
}

# Install dependencies for Arch Linux systems
install_dependencies_pacman() {
    log_info "Installing dependencies using pacman package manager"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would install dependencies using pacman"
        return 0
    fi
    
    # Update package database
    execute_cmd "sudo pacman -Sy" "Update package database"
    
    # Essential packages
    local essential_packages=(
        "curl" "wget" "jq" "openssl" "tar" "gzip"
        "docker" "docker-compose" "nginx" "certbot"
        "ufw" "fail2ban" "apparmor" "audit"
        "lsof" "bind-tools" "net-tools" "iputils"
        "noto-fonts" "noto-fonts-emoji" "ttf-dejavu"
    )
    
    execute_cmd "sudo pacman -S --noconfirm ${essential_packages[*]}" "Install essential packages"
}

# Auto-install missing dependencies
auto_install_dependencies() {
    log_section "Auto-Installing Missing Dependencies"
    
    local package_manager
    package_manager=$(detect_package_manager)
    
    log_info "Detected package manager: $package_manager"
    
    case "$package_manager" in
        "apt")
            install_dependencies_apt
            ;;
        "yum")
            install_dependencies_yum
            ;;
        "pacman")
            install_dependencies_pacman
            ;;
        *)
            log_error "Unsupported package manager: $package_manager"
            log_info "Supported systems: Debian/Ubuntu (apt), RHEL/CentOS (yum), Arch Linux (pacman)"
            return 1
            ;;
    esac
    
    # Validate after installation
    log_info "Re-validating dependencies after installation"
    if validate_all_dependencies; then
        log_success "Dependency validation passed"
        
        # Perform comprehensive verification
        if verify_installation_success; then
            log_success "Installation and verification completed successfully"
            return 0
        else
            log_error "Installation verification failed - some dependencies may not be functional"
            return 1
        fi
    else
        log_error "Dependency validation failed after installation"
        return 1
    fi
}

# Verify installation success by checking actual command availability and functionality
verify_installation_success() {
    log_info "Verifying installation success"
    
    local critical_commands=(
        "docker" "curl" "wget" "jq" "openssl" "nginx" "certbot" "ufw" "systemctl"
    )
    
    local verification_failed=false
    
    for cmd in "${critical_commands[@]}"; do
        if command_exists "$cmd"; then
            log_success "✓ $cmd available"
        else
            log_error "✗ $cmd missing after installation"
            verification_failed=true
        fi
    done
    
    # Special check for docker-compose compatibility
    if docker compose version &>/dev/null 2>&1; then
        log_success "✓ docker compose plugin available"
    elif command_exists docker-compose; then
        log_success "✓ docker-compose standalone available"
    else
        log_error "✗ docker compose not available in any form"
        verification_failed=true
    fi
    
    # Functional validation for critical tools
    log_info "Validating critical tool functionality"
    
    # Test jq JSON processing functionality
    if command_exists jq; then
        if echo '{"test":true}' | jq .test >/dev/null 2>&1; then
            log_success "✓ jq JSON processing functional"
        else
            log_error "✗ jq present but not functional"
            verification_failed=true
        fi
    fi
    
    # Test openssl functionality
    if command_exists openssl; then
        if openssl version >/dev/null 2>&1; then
            log_success "✓ openssl functional"
        else
            log_error "✗ openssl present but not functional"
            verification_failed=true
        fi
    fi
    
    # Test docker functionality (if available)
    if command_exists docker; then
        if docker version >/dev/null 2>&1; then
            log_success "✓ docker functional"
        else
            log_warning "⚠ docker present but may require service start"
        fi
    fi
    
    # Test systemctl functionality
    if command_exists systemctl; then
        if systemctl --version >/dev/null 2>&1; then
            log_success "✓ systemctl functional"
        else
            log_error "✗ systemctl present but not functional"
            verification_failed=true
        fi
    fi
    
    if $verification_failed; then
        log_error "Installation verification failed - some packages may not have installed correctly"
        log_info "This may indicate:"
        log_info "  - Package repository issues"
        log_info "  - Network connectivity problems"
        log_info "  - Insufficient system resources"
        log_info "  - Permission or dependency conflicts"
        return 1
    else
        log_success "Installation verification passed - all critical dependencies available and functional"
        return 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📋 DEPENDENCY REPORTING
# ═══════════════════════════════════════════════════════════════════════════════

# Generate dependency report
generate_dependency_report() {
    local report_file="${1:-$BASE_DIR/logs/dependency_report_$(date '+%Y%m%d_%H%M%S').txt}"
    
    log_info "Generating dependency report: $report_file"
    
    # Create report directory if needed
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
# JarvisJR Stack Dependency Report
Generated: $(date)
System: $(hostname)
OS: $(lsb_release -d 2>/dev/null | cut -f2- || uname -a)
Package Manager: $(detect_package_manager)

## Dependency Status Summary

EOF

    # Check each category and generate status
    local categories=(
        "Core System Tools:CORE_SYSTEM_TOOLS"
        "Network Tools:NETWORK_TOOLS"
        "JSON and Data Processing:DATA_PROCESSING_TOOLS"
        "Docker Tools:DOCKER_TOOLS"
        "System Monitoring:SYSTEM_MONITORING"
        "User Management:USER_MANAGEMENT"
        "Web Services:WEB_SERVICES"
        "Security Tools:SECURITY_TOOLS"
        "Package Managers:PACKAGE_MANAGERS"
        "Development Tools:DEVELOPMENT_TOOLS"
        "Monitoring Tools:MONITORING_TOOLS"
        "Text Processing:TEXT_PROCESSING"
        "Browser Tools:BROWSER_TOOLS"
    )
    
    for category_def in "${categories[@]}"; do
        IFS=':' read -r category_name category_var <<< "$category_def"
        local -n category_deps=$category_var
        
        echo "### $category_name" >> "$report_file"
        echo "" >> "$report_file"
        
        for cmd in "${!category_deps[@]}"; do
            IFS='|' read -r description package version usage <<< "${category_deps[$cmd]}"
            
            if command_exists "$cmd"; then
                echo "✓ **$cmd** - $description (Available)" >> "$report_file"
            else
                echo "✗ **$cmd** - $description (Missing - Package: $package)" >> "$report_file"
            fi
        done
        
        echo "" >> "$report_file"
    done
    
    # Add installation commands
    cat >> "$report_file" << EOF

## Installation Commands by Platform

### Debian/Ubuntu (apt)
\`\`\`bash
sudo apt-get update
sudo apt-get install -y curl wget jq openssl tar gzip docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nginx certbot python3-certbot-nginx ufw fail2ban apparmor apparmor-utils auditd lsb-release ca-certificates apt-transport-https software-properties-common gnupg lsof sysstat net-tools iputils-ping netcat-openbsd dnsutils
\`\`\`

### RHEL/CentOS (yum)
\`\`\`bash
sudo yum install -y curl wget jq openssl tar gzip nginx certbot python3-certbot-nginx firewalld fail2ban audit lsof bind-utils net-tools iputils
\`\`\`

### Arch Linux (pacman)
\`\`\`bash
sudo pacman -Sy
sudo pacman -S --noconfirm curl wget jq openssl tar gzip docker docker-compose nginx certbot ufw fail2ban apparmor audit lsof bind-tools net-tools iputils noto-fonts noto-fonts-emoji ttf-dejavu
\`\`\`

## Usage Context

EOF

    # Add usage context for critical dependencies
    local critical_deps=(
        "jq:Configuration parsing and JSON manipulation"
        "curl:HTTP requests, downloads, IP detection, API calls"
        "docker:Container runtime and management"
        "nginx:Reverse proxy and web server"
        "certbot:SSL certificate management"
        "openssl:Encryption, SSL certificates, secret generation"
        "ufw:Firewall configuration and management"
        "systemctl:Service management and control"
    )
    
    for dep_def in "${critical_deps[@]}"; do
        IFS=':' read -r cmd usage <<< "$dep_def"
        echo "- **$cmd**: $usage" >> "$report_file"
    done
    
    log_success "Dependency report generated: $report_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Main dependency management function
main() {
    case "${1:-validate}" in
        "validate"|"check")
            validate_all_dependencies
            ;;
        "install"|"setup")
            auto_install_dependencies
            ;;
        "report")
            generate_dependency_report "${2:-}"
            ;;
        "list")
            log_info "Available dependency categories:"
            echo "  - Core System Tools ($(echo ${!CORE_SYSTEM_TOOLS[@]} | wc -w) tools)"
            echo "  - Network Tools ($(echo ${!NETWORK_TOOLS[@]} | wc -w) tools)"
            echo "  - JSON and Data Processing ($(echo ${!DATA_PROCESSING_TOOLS[@]} | wc -w) tools)"
            echo "  - Docker Tools ($(echo ${!DOCKER_TOOLS[@]} | wc -w) tools)"
            echo "  - System Monitoring ($(echo ${!SYSTEM_MONITORING[@]} | wc -w) tools)"
            echo "  - User Management ($(echo ${!USER_MANAGEMENT[@]} | wc -w) tools)"
            echo "  - Web Services ($(echo ${!WEB_SERVICES[@]} | wc -w) tools)"
            echo "  - Security Tools ($(echo ${!SECURITY_TOOLS[@]} | wc -w) tools)"
            echo "  - Package Managers ($(echo ${!PACKAGE_MANAGERS[@]} | wc -w) tools)"
            echo "  - Development Tools ($(echo ${!DEVELOPMENT_TOOLS[@]} | wc -w) tools)"
            echo "  - Monitoring Tools ($(echo ${!MONITORING_TOOLS[@]} | wc -w) tools)"
            echo "  - Text Processing ($(echo ${!TEXT_PROCESSING[@]} | wc -w) tools)"
            echo "  - Browser Tools ($(echo ${!BROWSER_TOOLS[@]} | wc -w) tools)"
            ;;
        *)
            echo "JarvisJR Stack Dependency Management"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  validate, check       Validate all dependencies"
            echo "  install, setup        Install missing dependencies"
            echo "  report [FILE]         Generate dependency report"
            echo "  list                  List dependency categories"
            echo ""
            echo "Examples:"
            echo "  $0 validate           # Check all dependencies"
            echo "  $0 install            # Install missing dependencies"
            echo "  $0 report             # Generate dependency report"
            echo "  $0 list               # Show dependency categories"
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi