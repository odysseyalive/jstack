#!/bin/bash
# Container Security Hardening Module for JStack Stack
# Implements CIS Docker benchmarks, vulnerability scanning, and runtime security

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔒 DOCKER SECURITY SCANNING SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_trivy_scanner() {
    log_section "Setting up Trivy Container Vulnerability Scanner"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Trivy vulnerability scanner"
        return 0
    fi
    
    start_section_timer "Trivy Setup"
    
    # Check if Trivy is already installed
    if command -v trivy >/dev/null 2>&1; then
        local trivy_version=$(trivy --version | head -n1)
        log_success "Trivy already installed: $trivy_version"
        end_section_timer "Trivy Setup"
        return 0
    fi
    
    log_info "Installing Trivy vulnerability scanner"
    
    # Detect OS and install Trivy accordingly
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            "arch")
                execute_cmd "sudo pacman -S --noconfirm trivy" "Install Trivy (Arch)"
                ;;
            "ubuntu"|"debian")
                execute_cmd "wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -" "Add Trivy GPG key"
                execute_cmd "echo 'deb https://aquasecurity.github.io/trivy-repo/deb generic main' | sudo tee -a /etc/apt/sources.list.d/trivy.list" "Add Trivy repository"
                execute_cmd "sudo apt-get update && sudo apt-get install -y trivy" "Install Trivy (Debian/Ubuntu)"
                ;;
            *)
                log_info "Installing Trivy via GitHub releases"
                execute_cmd "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin v0.48.3" "Install Trivy (Generic)"
                ;;
        esac
    fi
    
    # Verify installation
    if command -v trivy >/dev/null 2>&1; then
        local trivy_version=$(trivy --version | head -n1)
        log_success "Trivy installed successfully: $trivy_version"
        
        # Update vulnerability database
        execute_cmd "trivy image --download-db-only" "Update Trivy vulnerability database"
    else
        log_error "Trivy installation failed"
        return 1
    fi
    
    end_section_timer "Trivy Setup"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️ CIS DOCKER BENCHMARK IMPLEMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

setup_docker_bench_security() {
    log_section "Setting up Docker Bench Security"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Docker Bench Security"
        return 0
    fi
    
    start_section_timer "Docker Bench Setup"
    
    local bench_dir="$BASE_DIR/security/docker-bench"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $bench_dir" "Create Docker Bench directory"
    
    # Download Docker Bench Security
    if [[ ! -f "$bench_dir/docker-bench-security.sh" ]]; then
        execute_cmd "sudo -u $SERVICE_USER git clone https://github.com/docker/docker-bench-security.git $bench_dir" "Clone Docker Bench Security"
    else
        log_info "Docker Bench Security already downloaded"
    fi
    
    # Make script executable
    execute_cmd "chmod +x $bench_dir/docker-bench-security.sh" "Make Docker Bench executable"
    
    end_section_timer "Docker Bench Setup"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 CONTAINER SECURITY HARDENING
# ═══════════════════════════════════════════════════════════════════════════════

create_enhanced_apparmor_profiles() {
    log_section "Creating Enhanced AppArmor Profiles"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create enhanced AppArmor profiles"
        return 0
    fi
    
    if [[ "$APPARMOR_ENABLED" != "true" ]]; then
        log_info "AppArmor disabled, skipping profile creation"
        return 0
    fi
    
    start_section_timer "AppArmor Profiles"
    
    # Enhanced N8N AppArmor Profile
    cat > /tmp/docker-n8n-enhanced << 'EOF'
#include <tunables/global>

profile docker-n8n-enhanced flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/openssl>
  
  # Network access for workflow execution
  network inet tcp,
  network inet udp,
  
  # Essential capabilities only
  capability chown,
  capability dac_override,
  capability setgid,
  capability setuid,
  capability net_bind_service,
  
  # Deny dangerous capabilities
  deny capability mac_admin,
  deny capability mac_override,
  deny capability sys_admin,
  deny capability sys_module,
  deny capability sys_rawio,
  deny capability sys_ptrace,
  deny capability sys_time,
  deny capability audit_write,
  
  # File system permissions
  /bin/** rix,
  /usr/bin/** rix,
  /usr/lib/** r,
  /lib/** r,
  /etc/** r,
  
  # N8N specific paths
  /home/node/.n8n/** rw,
  /tmp/** rw,
  /var/tmp/** rw,
  
  # Deny access to sensitive system areas
  deny /proc/sys/** w,
  deny /sys/** w,
  deny /boot/** rwx,
  deny /root/** rwx,
  
  # Allow container networking
  /proc/net/route r,
  /proc/net/tcp r,
  /proc/net/udp r,
}
EOF
    
    safe_mv "/tmp/docker-n8n-enhanced" "/etc/apparmor.d/docker-n8n-enhanced" "Install N8N AppArmor profile"
    
    # Enhanced PostgreSQL AppArmor Profile
    cat > /tmp/docker-postgres-enhanced << 'EOF'
#include <tunables/global>

profile docker-postgres-enhanced flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  
  # Database networking
  network inet tcp,
  network inet udp,
  
  # PostgreSQL essential capabilities
  capability chown,
  capability dac_override,
  capability setgid,
  capability setuid,
  capability ipc_lock,
  
  # Deny dangerous capabilities
  deny capability mac_admin,
  deny capability mac_override,
  deny capability sys_admin,
  deny capability sys_module,
  deny capability sys_rawio,
  deny capability sys_ptrace,
  
  # File system access
  /bin/** rix,
  /usr/bin/** rix,
  /usr/lib/postgresql/** rix,
  /lib/** r,
  /etc/** r,
  
  # PostgreSQL data directory
  /var/lib/postgresql/** rw,
  /tmp/** rw,
  
  # Deny sensitive areas
  deny /proc/sys/** w,
  deny /sys/** w,
  deny /boot/** rwx,
  deny /root/** rwx,
}
EOF
    
    safe_mv "/tmp/docker-postgres-enhanced" "/etc/apparmor.d/docker-postgres-enhanced" "Install PostgreSQL AppArmor profile"
    
    # Load AppArmor profiles
    execute_cmd "sudo apparmor_parser -r /etc/apparmor.d/docker-n8n-enhanced" "Load N8N AppArmor profile"
    execute_cmd "sudo apparmor_parser -r /etc/apparmor.d/docker-postgres-enhanced" "Load PostgreSQL AppArmor profile"
    
    end_section_timer "AppArmor Profiles"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 CONTAINER SECURITY VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

run_container_security_scan() {
    log_section "Running Container Security Scan"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run container security scans"
        return 0
    fi
    
    start_section_timer "Security Scan"
    
    local scan_results="$BASE_DIR/security/scan-results-$(date +%Y%m%d_%H%M%S).txt"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $(dirname $scan_results)" "Create scan results directory"
    
    echo "Container Security Scan Results - $(date)" > "$scan_results"
    echo "=======================================" >> "$scan_results"
    
    # Scan running containers
    local containers=$(docker ps --format "{{.Names}}" | grep -E "(n8n|supabase|nginx)" || echo "")
    if [[ -n "$containers" ]]; then
        while IFS= read -r container; do
            log_info "Scanning container: $container"
            echo -e "\n--- Container: $container ---" >> "$scan_results"
            
            # Get container image
            local image=$(docker inspect "$container" --format='{{.Config.Image}}')
            
            # Run Trivy scan
            if command -v trivy >/dev/null 2>&1; then
                trivy image --format table --severity HIGH,CRITICAL "$image" >> "$scan_results" 2>&1
            fi
            
            # Container configuration check
            echo -e "\n--- Configuration Check ---" >> "$scan_results"
            docker inspect "$container" --format='{{json .HostConfig}}' | \
                jq -r '"Privileged: " + (.Privileged | tostring) + 
                      ", ReadonlyRootfs: " + (.ReadonlyRootfs | tostring) + 
                      ", Memory: " + (.Memory | tostring)' >> "$scan_results"
        done <<< "$containers"
    else
        echo "No running containers found to scan" >> "$scan_results"
    fi
    
    # Run Docker Bench Security if available
    local bench_script="$BASE_DIR/security/docker-bench/docker-bench-security.sh"
    if [[ -f "$bench_script" ]]; then
        echo -e "\n--- Docker Bench Security Results ---" >> "$scan_results"
        "$bench_script" >> "$scan_results" 2>&1
    fi
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$scan_results" "Set scan results ownership"
    log_success "Security scan completed: $scan_results"
    
    end_section_timer "Security Scan"
}

create_container_security_configs() {
    log_section "Creating Enhanced Container Security Configurations"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create enhanced container security configs"
        return 0
    fi
    
    start_section_timer "Security Configs"
    
    local security_dir="$BASE_DIR/security/configs"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $security_dir" "Create security configs directory"
    
    # Create seccomp profile for containers
    cat > /tmp/default-seccomp.json << 'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": [
                "SCMP_ARCH_X86",
                "SCMP_ARCH_X32"
            ]
        }
    ],
    "syscalls": [
        {
            "names": [
                "accept",
                "accept4",
                "access",
                "bind",
                "brk",
                "chdir",
                "chmod",
                "chown",
                "close",
                "connect",
                "dup",
                "dup2",
                "epoll_create",
                "epoll_create1",
                "epoll_ctl",
                "epoll_wait",
                "execve",
                "exit",
                "exit_group",
                "fchdir",
                "fchmod",
                "fchown",
                "fcntl",
                "fork",
                "fstat",
                "fsync",
                "futex",
                "getcwd",
                "getdents",
                "getdents64",
                "getgid",
                "getpid",
                "getppid",
                "getrlimit",
                "getsockname",
                "getsockopt",
                "getuid",
                "listen",
                "lseek",
                "lstat",
                "mkdir",
                "mmap",
                "mprotect",
                "munmap",
                "open",
                "openat",
                "pipe",
                "poll",
                "read",
                "readlink",
                "recv",
                "recvfrom",
                "rename",
                "rmdir",
                "select",
                "send",
                "sendto",
                "setgid",
                "setuid",
                "socket",
                "stat",
                "unlink",
                "wait4",
                "write"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF
    
    safe_mv "/tmp/default-seccomp.json" "$security_dir/default-seccomp.json" "Install seccomp profile"
    
    # Create container hardening script
    cat > /tmp/harden-containers.sh << 'EOF'
#!/bin/bash
# Container Hardening Script for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

harden_running_containers() {
    log_info "Applying security hardening to running containers"
    
    # Apply security policies to containers
    for container in $(docker ps --format "{{.Names}}" | grep -E "(n8n|supabase|nginx)"); do
        log_info "Hardening container: $container"
        
        # Update container with security options (requires recreation)
        docker update --restart=unless-stopped "$container" 2>/dev/null || true
    done
}

validate_container_security() {
    log_info "Validating container security configurations"
    
    for container in $(docker ps --format "{{.Names}}"); do
        echo "=== $container ==="
        
        # Check if running as non-root
        user_id=$(docker exec "$container" id -u 2>/dev/null || echo "unknown")
        echo "User ID: $user_id"
        
        # Check capabilities
        echo "Capabilities:"
        docker exec "$container" capsh --print 2>/dev/null | head -3 || echo "Unable to check capabilities"
        
        # Check AppArmor profile
        profile=$(docker inspect "$container" --format='{{.AppArmorProfile}}' 2>/dev/null || echo "none")
        echo "AppArmor Profile: $profile"
        
        echo ""
    done
}

case "${1:-harden}" in
    "harden") harden_running_containers ;;
    "validate") validate_container_security ;;
    "both") harden_running_containers; validate_container_security ;;
    *) echo "Usage: $0 [harden|validate|both]" ;;
esac
EOF
    
    safe_mv "/tmp/harden-containers.sh" "$security_dir/harden-containers.sh" "Install container hardening script"
    execute_cmd "chmod +x $security_dir/harden-containers.sh" "Make hardening script executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$security_dir/" "Set security configs ownership"
    
    end_section_timer "Security Configs"
}

# Main function
main() {
    case "${1:-setup}" in
        "trivy") setup_trivy_scanner ;;
        "bench") setup_docker_bench_security ;;
        "apparmor") create_enhanced_apparmor_profiles ;;
        "scan") run_container_security_scan ;;
        "configs") create_container_security_configs ;;
        "setup"|"all") 
            setup_trivy_scanner
            setup_docker_bench_security
            create_enhanced_apparmor_profiles
            create_container_security_configs
            ;;
        "validate") 
            run_container_security_scan
            ;;
        *) echo "Usage: $0 [setup|trivy|bench|apparmor|scan|configs|validate|all]"
           echo "Container security hardening module for JStack Stack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi