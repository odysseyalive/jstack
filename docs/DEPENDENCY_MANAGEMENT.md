# JarvisJR Stack Dependency Management

This document describes the comprehensive dependency management system implemented for the JarvisJR Stack, ensuring all required tools and packages are available before installation and operation.

## Overview

The JarvisJR Stack dependency management system provides:

- **Comprehensive Cataloging**: Complete inventory of all dependencies across 35+ shell scripts
- **Automated Validation**: Pre-installation and runtime dependency checking
- **Platform Support**: Debian/Ubuntu (apt), RHEL/CentOS (yum/dnf), Arch Linux (pacman)
- **Centralized Installation**: Automated installation of missing dependencies
- **Detailed Reporting**: Dependency status reports and installation guides

## System Architecture

### Core Components

1. **`scripts/core/dependency_management.sh`** - Main dependency management system
2. **`scripts/core/install_dependencies.sh`** - Quick dependency installer
3. **`scripts/core/pre_installation_check.sh`** - Pre-installation validation
4. **`DEPENDENCY_MANIFEST.md`** - Complete dependency catalog and documentation

### Dependency Categories

The system categorizes dependencies into 13 categories:

| Category | Count | Criticality | Description |
|----------|-------|-------------|-------------|
| Core System Tools | 21 | Critical | Basic shell and file operations |
| Network Utilities | 9 | Critical | HTTP, DNS, network connectivity |
| JSON/Data Processing | 6 | Critical | Configuration parsing, encryption |
| Docker Ecosystem | 2 | Critical | Container runtime and orchestration |
| System Monitoring | 14 | Required | Process, memory, disk monitoring |
| User Management | 3 | Required | User and group operations |
| Web Services | 2 | Critical | NGINX, SSL certificates |
| Security Tools | 7 | Required | Firewall, intrusion prevention |
| Package Managers | 6 | Platform-specific | System package installation |
| Development Tools | 5 | Optional | Git, Node.js, Python |
| Monitoring Tools | 10 | Optional | Security scanning, diagnostics |
| Text Processing | 6 | Optional | Fonts for browser automation |
| Browser Tools | 3 | Optional | Chrome/Chromium for automation |

## Usage Guide

### Quick Start

```bash
# Install all dependencies automatically
./scripts/core/install_dependencies.sh

# Or run comprehensive dependency management
./scripts/core/dependency_management.sh install

# Validate existing dependencies
./scripts/core/dependency_management.sh validate

# Generate dependency report
./scripts/core/dependency_management.sh report
```

### Integration with JarvisJR Installation Flow

The dependency management system is fully integrated into the main JarvisJR Stack installation process:

1. **Automatic Integration**: Dependencies are checked and installed during Phase 1 of installation
2. **Pre-Installation Validation**: Critical dependencies are validated before any system changes
3. **Interactive Installation**: Users are prompted before dependency installation (unless using `--force-install`)
4. **Comprehensive Reporting**: Dependency status is logged and reported for troubleshooting

#### Installation Flow Integration

```bash
# Standard installation (includes dependency management)
./jstack.sh

# Force installation without prompts
./jstack.sh --force-install

# Dry-run mode (shows what dependencies would be installed)
./jstack.sh --dry-run
```

## Detailed Component Documentation

### Core Scripts

#### `scripts/core/dependency_management.sh`

The main dependency management system providing comprehensive cataloging, validation, and installation of all JarvisJR Stack dependencies.

**Key Functions:**
- `validate_all_dependencies()` - Validates all 85+ dependencies across 13 categories
- `auto_install_dependencies()` - Installs missing dependencies based on platform
- `generate_dependency_report()` - Creates detailed dependency status reports
- `command_exists()` - Checks if a command is available in PATH

**Usage:**
```bash
# Validate all dependencies
./scripts/core/dependency_management.sh validate

# Install missing dependencies  
./scripts/core/dependency_management.sh install

# Generate report
./scripts/core/dependency_management.sh report [output-file]

# List dependency categories
./scripts/core/dependency_management.sh list
```

#### `scripts/core/install_dependencies.sh`

Quick dependency installer designed for bootstrap scenarios where the full dependency management system may not be available.

**Features:**
- Platform detection (Debian/Ubuntu, RHEL/CentOS, Arch Linux)
- Essential-only installation for minimal functionality
- Fallback installation when dependency_management.sh is unavailable
- Docker installation and configuration

**Usage:**
```bash
# Install essential dependencies
./scripts/core/install_dependencies.sh install

# Validate installation
./scripts/core/install_dependencies.sh check
```

#### `scripts/core/pre_installation_check.sh`

Pre-installation validation system that checks critical dependencies before any system modifications.

**Validation Scope:**
- Critical dependencies (installation blockers)
- Optional dependencies (feature limitations)
- Docker daemon availability and health
- Service management capabilities

**Usage:**
```bash
# Complete pre-installation check
./scripts/core/pre_installation_check.sh check

# Check dependencies only
./scripts/core/pre_installation_check.sh dependencies

# Check Docker specifically
./scripts/core/pre_installation_check.sh docker
```

## Platform-Specific Installation

### Debian/Ubuntu (apt-based systems)

#### Repository Setup
```bash
# Update package lists
sudo apt-get update -y

# Install essential repositories
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release
```

#### Docker Installation
```bash
# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

#### Essential Package Installation
```bash
# Core system tools and utilities
sudo apt-get install -y \
    curl wget jq openssl tar gzip \
    nginx certbot python3-certbot-nginx \
    ufw fail2ban apparmor apparmor-utils auditd \
    lsof sysstat net-tools iputils-ping netcat-openbsd dnsutils \
    fonts-noto fonts-noto-color-emoji fonts-dejavu-core

# Browser automation dependencies
sudo apt-get install -y \
    libnss3 libatk-bridge2.0-0 libdrm2 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    libxss1 libasound2
```

### RHEL/CentOS (yum/dnf-based systems)

#### Repository Setup
```bash
# Install EPEL repository (for additional packages)
sudo yum install -y epel-release

# Update package lists
sudo yum update -y
```

#### Docker Installation
```bash
# Install required packages
sudo yum install -y yum-utils

# Add Docker repository
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

#### Essential Package Installation
```bash
# Core system tools and utilities
sudo yum install -y \
    curl wget jq openssl tar gzip \
    nginx certbot python3-certbot-nginx \
    firewalld fail2ban audit \
    lsof bind-utils net-tools iputils
```

### Arch Linux (pacman-based systems)

#### Package Installation
```bash
# Update package database
sudo pacman -Sy

# Install essential packages
sudo pacman -S --noconfirm \
    curl wget jq openssl tar gzip \
    docker docker-compose nginx certbot \
    ufw fail2ban apparmor audit \
    lsof bind-tools net-tools iputils \
    noto-fonts noto-fonts-emoji ttf-dejavu

# Enable Docker service
sudo systemctl enable docker
sudo systemctl start docker
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Missing JSON Processor (jq)

**Problem**: Many scripts fail with "jq: command not found"

**Solution**:
```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y jq

# RHEL/CentOS
sudo yum install -y jq

# Arch Linux
sudo pacman -S jq
```

**Root Cause**: jq is critical for configuration parsing and API response handling across all JarvisJR components.

#### 2. Docker Not Available

**Problem**: "docker: command not found" or daemon not running

**Solutions**:
```bash
# Check if Docker is installed
docker --version

# Install Docker (automated)
curl -fsSL https://get.docker.com | sh

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group (optional)
sudo usermod -aG docker $USER
newgrp docker
```

**Root Cause**: Docker is the core platform for JarvisJR Stack containerized services.

#### 3. Network Utilities Missing

**Problem**: Domain validation fails or network connectivity issues

**Solutions**:
```bash
# Debian/Ubuntu
sudo apt-get install -y dnsutils net-tools iputils-ping netcat-openbsd

# RHEL/CentOS  
sudo yum install -y bind-utils net-tools iputils

# Arch Linux
sudo pacman -S bind-tools net-tools iputils
```

**Root Cause**: Network utilities are required for domain validation, connectivity testing, and SSL certificate management.

#### 4. SSL/Cryptography Issues

**Problem**: SSL certificate generation fails or crypto operations fail

**Solutions**:
```bash
# Ensure OpenSSL is installed and up to date
openssl version

# Install/update OpenSSL
# Debian/Ubuntu
sudo apt-get install -y openssl

# RHEL/CentOS
sudo yum install -y openssl

# Arch Linux
sudo pacman -S openssl
```

**Root Cause**: OpenSSL is required for certificate generation, encryption, and secure secret management.

#### 5. Browser Automation Failures

**Problem**: Chrome/Chromium not available or missing fonts

**Solutions**:
```bash
# Install Chrome (Debian/Ubuntu)
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt-get update
sudo apt-get install -y google-chrome-stable

# Install font packages
# Debian/Ubuntu
sudo apt-get install -y fonts-noto fonts-noto-color-emoji fonts-dejavu-core

# Arch Linux  
sudo pacman -S noto-fonts noto-fonts-emoji ttf-dejavu
```

**Root Cause**: Browser automation requires Chrome/Chromium and proper font rendering support.

#### 6. Permission Issues

**Problem**: "Permission denied" errors during installation

**Solutions**:
```bash
# Check sudo access
sudo -v

# Configure passwordless sudo (if needed)
./jstack.sh --configure-sudo

# Manual sudo configuration
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$USER

# Fix file permissions
sudo chown -R $USER:$USER ~/.local/share/JarvisJR
```

**Root Cause**: JarvisJR requires sudo access for system configuration and service management.

### Diagnostic Commands

#### System Information
```bash
# OS and distribution info
lsb_release -a
uname -a
cat /etc/os-release

# Package manager detection
which apt-get yum dnf pacman

# Available memory and disk space
free -h
df -h
```

#### Dependency Validation
```bash
# Run comprehensive dependency check
./scripts/core/dependency_management.sh validate

# Generate detailed report
./scripts/core/dependency_management.sh report /tmp/dep_report.txt
cat /tmp/dep_report.txt

# Check specific categories
./scripts/core/pre_installation_check.sh dependencies
./scripts/core/pre_installation_check.sh docker
```

#### Network Connectivity
```bash
# Test internet connectivity
ping -c 4 8.8.8.8
curl -I https://httpbin.org/ip

# Test DNS resolution
dig google.com
nslookup google.com

# Check required ports
nc -zv localhost 80
nc -zv localhost 443
```

#### Docker Validation
```bash
# Docker version and info
docker --version
docker info

# Test Docker functionality
docker run hello-world

# Check Docker Compose
docker compose version
```

### Recovery Procedures

#### Full Dependency Reinstallation
```bash
# Clean package cache
sudo apt-get clean  # Debian/Ubuntu
sudo yum clean all  # RHEL/CentOS
sudo pacman -Scc    # Arch Linux

# Update package lists
sudo apt-get update -y     # Debian/Ubuntu
sudo yum update -y         # RHEL/CentOS
sudo pacman -Sy           # Arch Linux

# Reinstall all dependencies
./scripts/core/dependency_management.sh install
```

#### Docker Reinstallation
```bash
# Complete Docker removal and reinstall
./jstack.sh --uninstall-docker
./scripts/core/install_dependencies.sh install
```

#### System Reset
```bash
# Complete JarvisJR uninstallation
./jstack.sh --uninstall

# Clean dependency installation  
./scripts/core/install_dependencies.sh install

# Fresh installation
./jstack.sh
```

## Advanced Configuration

### Custom Dependency Sets

For specialized deployments, you can customize which dependencies are installed:

```bash
# Install only critical dependencies
INSTALL_OPTIONAL="false" ./scripts/core/dependency_management.sh install

# Skip browser automation dependencies
SKIP_BROWSER="true" ./scripts/core/dependency_management.sh install

# Development mode (includes all optional tools)
DEVELOPMENT_MODE="true" ./scripts/core/dependency_management.sh install
```

### Platform-Specific Optimizations

#### Debian/Ubuntu Optimizations
```bash
# Enable universe repository for additional packages
sudo add-apt-repository universe

# Install snap support for universal packages
sudo apt-get install -y snapd

# Configure automatic security updates
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades
```

#### RHEL/CentOS Optimizations
```bash
# Enable additional repositories
sudo yum install -y centos-release-scl  # Software Collections
sudo yum install -y epel-release        # Extra Packages

# Configure automatic updates
sudo yum install -y yum-cron
sudo systemctl enable yum-cron
```

#### Arch Linux Optimizations
```bash
# Enable multilib repository
echo '[multilib]' | sudo tee -a /etc/pacman.conf
echo 'Include = /etc/pacman.d/mirrorlist' | sudo tee -a /etc/pacman.conf

# Install AUR helper for additional packages
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si
```

## Security Considerations

### Dependency Security

1. **Package Verification**: All packages are installed from official repositories with GPG verification
2. **Minimal Installation**: Only required dependencies are installed by default
3. **Regular Updates**: Dependencies should be updated regularly for security patches
4. **Audit Trail**: All dependency installations are logged for security auditing

### Repository Security

```bash
# Verify repository signatures (Debian/Ubuntu)
sudo apt-key list
sudo apt update 2>&1 | grep -i signature

# Check package signatures (RHEL/CentOS)
rpm --checksig $(which docker)

# Verify package integrity (Arch Linux)
pacman -Qkk
```

### Security Monitoring

```bash
# Monitor for security updates
# Debian/Ubuntu
sudo apt list --upgradable | grep -i security

# RHEL/CentOS
sudo yum check-update --security

# Arch Linux
checkupdates
```

## Performance Optimization

### Dependency Installation Speed

1. **Parallel Installation**: Where possible, dependencies are installed in parallel
2. **Package Caching**: Package managers cache downloads to speed up repeated installations
3. **Mirror Selection**: Use fastest package mirrors for your geographic location

### Resource Usage

The dependency management system is designed for minimal resource usage:
- **Memory**: <100MB during installation
- **Disk**: <2GB for all dependencies
- **Network**: Packages are downloaded on-demand only

## Maintenance and Updates

### Regular Maintenance Tasks

```bash
# Weekly dependency validation
0 2 * * 0 cd /path/to/jstack && ./scripts/core/dependency_management.sh validate

# Monthly dependency report
0 3 1 * * cd /path/to/jstack && ./scripts/core/dependency_management.sh report

# Security update check
0 6 * * * apt list --upgradable 2>/dev/null | grep -i security | mail -s "Security Updates Available" admin@example.com
```

### Upgrade Procedures

```bash
# Update all system packages
sudo apt-get update && sudo apt-get upgrade -y  # Debian/Ubuntu
sudo yum update -y                              # RHEL/CentOS  
sudo pacman -Syu                               # Arch Linux

# Validate dependencies after system upgrade
./scripts/core/dependency_management.sh validate

# Reinstall any missing dependencies
./scripts/core/dependency_management.sh install
```

---

This comprehensive dependency management system ensures reliable, secure, and maintainable deployment of the JarvisJR Stack across all supported platforms while providing extensive troubleshooting and maintenance capabilities

# Validate dependency installation
./scripts/core/dependency_management.sh validate

# Start JarvisJR installation
./jstack.sh
```

### Pre-Installation Check

Before running JarvisJR installation:

```bash
# Complete pre-installation validation
./scripts/core/pre_installation_check.sh

# Check only critical dependencies
./scripts/core/pre_installation_check.sh dependencies

# Check Docker specifically
./scripts/core/pre_installation_check.sh docker
```

### Comprehensive Dependency Management

```bash
# Validate all dependencies
./scripts/core/dependency_management.sh validate

# Install missing dependencies
./scripts/core/dependency_management.sh install

# Generate detailed report
./scripts/core/dependency_management.sh report

# List dependency categories
./scripts/core/dependency_management.sh list
```

## Integration with JarvisJR Installation

The dependency management system integrates with the main JarvisJR installation flow:

### Automated Integration

The main `jstack.sh` script automatically calls dependency validation during the setup phase:

1. **Phase 0**: Dependency validation (new)
2. **Phase 1**: System setup and validation
3. **Phase 2**: Container deployment
4. **Phase 3**: SSL configuration
5. **Phase 4**: Service orchestration

### Manual Override

If dependency validation fails, users can:

1. **Auto-install**: `./scripts/core/install_dependencies.sh`
2. **Force install**: `./jstack.sh --force-install` (not recommended)
3. **Manual install**: Follow platform-specific instructions in `DEPENDENCY_MANIFEST.md`

## Platform-Specific Implementation

### Debian/Ubuntu (APT)

```bash
# Essential packages
sudo apt-get install -y \
    curl wget jq openssl tar gzip \
    docker-ce docker-ce-cli containerd.io \
    nginx certbot python3-certbot-nginx \
    ufw fail2ban apparmor apparmor-utils auditd

# Optional monitoring
sudo apt-get install -y \
    sysstat net-tools iputils-ping netcat-openbsd \
    dnsutils nmap lynis chkrootkit rkhunter

# Browser automation support
sudo apt-get install -y \
    fonts-noto fonts-noto-color-emoji fonts-dejavu-core \
    libnss3 libatk-bridge2.0-0 libxkbcommon0
```

### RHEL/CentOS (YUM/DNF)

```bash
# Essential packages
sudo yum install -y \
    curl wget jq openssl tar gzip \
    nginx certbot python3-certbot-nginx \
    firewalld fail2ban audit \
    lsof bind-utils net-tools iputils

# Docker (via official installer)
curl -fsSL https://get.docker.com | sh
```

### Arch Linux (Pacman)

```bash
# Essential packages
sudo pacman -S --noconfirm \
    curl wget jq openssl tar gzip \
    docker docker-compose nginx certbot \
    ufw fail2ban apparmor audit \
    lsof bind-tools net-tools iputils \
    noto-fonts noto-fonts-emoji ttf-dejavu
```

## Dependency Validation Logic

### Critical Dependencies

These dependencies are **required** for JarvisJR operation:

- **System Tools**: `bash`, `sudo`, `systemctl`, file operations
- **Network**: `curl`, `wget` (downloads, API calls)
- **Data Processing**: `jq` (configuration parsing), `openssl` (encryption)
- **Container Platform**: `docker`, `docker-compose`
- **Web Services**: `nginx`, `certbot`
- **Security**: `ufw`, `fail2ban`

### Optional Dependencies

These dependencies enhance functionality but are not required:

- **Monitoring**: `iostat`, `nmap`, `lynis`
- **Development**: `git`, `npm`, `python3`
- **Browser Automation**: `google-chrome`, fonts
- **Enhanced Security**: `trivy`, `falco`

### Validation Process

1. **Command Availability**: Check if commands exist using `command -v`
2. **Service Status**: Validate Docker daemon status
3. **Version Compatibility**: Check minimum version requirements
4. **Platform Detection**: Identify package manager and OS
5. **Error Reporting**: Detailed failure analysis and remediation

## Error Handling and Recovery

### Common Issues

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| Missing `jq` | Configuration parsing failures | `sudo apt-get install -y jq` |
| Docker not running | Container operations fail | `sudo systemctl start docker` |
| Network tools missing | Domain validation fails | Install `dnsutils` package |
| SSL tools missing | Certificate management fails | Install `openssl`, `certbot` |

### Recovery Procedures

1. **Automatic Recovery**:
   ```bash
   ./scripts/core/install_dependencies.sh
   ```

2. **Manual Recovery**:
   ```bash
   # Check what's missing
   ./scripts/core/dependency_management.sh validate
   
   # Generate installation guide
   ./scripts/core/dependency_management.sh report
   
   # Install manually using platform package manager
   ```

3. **Force Installation** (if dependencies can't be resolved):
   ```bash
   ./jstack.sh --force-install
   ```

## Monitoring and Maintenance

### Regular Dependency Audits

Set up periodic dependency validation:

```bash
# Add to crontab for weekly checks
0 2 * * 0 cd /path/to/jstack && ./scripts/core/dependency_management.sh validate

# Monthly detailed reports
0 3 1 * * cd /path/to/jstack && ./scripts/core/dependency_management.sh report
```

### Security Updates

Critical dependencies requiring regular updates:

- **Docker**: Follow Docker security advisories
- **NGINX**: Apply security patches promptly
- **OpenSSL**: Critical for all SSL/TLS operations
- **System packages**: Regular OS security updates
- **Browser**: Keep Chrome/Chromium updated for automation

### Dependency Evolution

As JarvisJR Stack evolves, the dependency system supports:

1. **Adding new dependencies**: Update catalog arrays in `dependency_management.sh`
2. **Version updates**: Modify minimum version requirements
3. **Platform support**: Add new package managers
4. **Optional features**: Categorize as optional vs. critical

## Advanced Features

### Custom Dependency Profiles

The system supports custom dependency profiles for different deployment scenarios:

- **Minimal**: Only critical dependencies
- **Standard**: Critical + recommended dependencies
- **Enhanced**: All dependencies including monitoring and security tools
- **Development**: Additional development and debugging tools

### Integration with CI/CD

For automated deployments:

```bash
# Validate dependencies in CI pipeline
./scripts/core/dependency_management.sh validate || exit 1

# Generate dependency report for deployment documentation
./scripts/core/dependency_management.sh report /tmp/dependencies.md
```

### Docker-based Dependency Management

For containerized dependency management:

```bash
# Use Docker to validate dependencies without installation
docker run --rm -v "$PWD:/workspace" ubuntu:22.04 \
    bash -c "cd /workspace && ./scripts/core/dependency_management.sh validate"
```

## Troubleshooting Guide

### Debug Mode

Enable verbose dependency checking:

```bash
# Enable debug logging
export ENABLE_DEBUG_LOGS=true
./scripts/core/dependency_management.sh validate
```

### Common Resolution Steps

1. **Update package lists**: `sudo apt-get update`
2. **Check repository configuration**: Ensure proper repositories are enabled
3. **Verify network connectivity**: Check internet access for downloads
4. **Clean package cache**: `sudo apt-get clean && sudo apt-get update`
5. **Check disk space**: Ensure sufficient space for package installation

### Support Resources

- **Dependency Manifest**: `DEPENDENCY_MANIFEST.md` - Complete dependency catalog
- **Installation Logs**: `$BASE_DIR/logs/dependency_*.log` - Detailed installation logs
- **System Reports**: Generated by `dependency_management.sh report`
- **Pre-installation Check**: `pre_installation_check.sh` - Validation before installation

---

This dependency management system ensures reliable, automated installation and operation of the JarvisJR Stack across multiple Linux distributions and deployment scenarios.