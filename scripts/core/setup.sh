#!/bin/bash
# System setup and initialization for COMPASS Stack
# Handles OS hardening, user setup, and prerequisite installation

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"
source "${PROJECT_ROOT}/scripts/lib/validation.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️ HOST OS HARDENING
# ═══════════════════════════════════════════════════════════════════════════════

harden_host_os() {
    log_section "Host OS Security Hardening"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would perform OS hardening"
        return 0
    fi
    
    start_section_timer "OS Hardening"
    
    # Update system packages
    log_info "Updating system packages"
    execute_cmd "sudo apt-get update -y" "Update package lists"
    execute_cmd "sudo apt-get upgrade -y" "Upgrade system packages"
    execute_cmd "sudo apt-get autoremove -y" "Remove unnecessary packages"
    
    # Install essential security packages
    log_info "Installing security packages"
    execute_cmd "sudo apt-get install -y ufw fail2ban apparmor apparmor-utils auditd" "Install security packages"
    
    # Configure UFW firewall
    log_info "Configuring UFW firewall"
    execute_cmd "sudo ufw --force reset" "Reset UFW to defaults"
    execute_cmd "sudo ufw default deny incoming" "Set default deny incoming"
    execute_cmd "sudo ufw default allow outgoing" "Set default allow outgoing"
    execute_cmd "sudo ufw allow ssh" "Allow SSH"
    execute_cmd "sudo ufw allow 80" "Allow HTTP"
    execute_cmd "sudo ufw allow 443" "Allow HTTPS"
    execute_cmd "sudo ufw --force enable" "Enable UFW"
    
    # Configure fail2ban
    log_info "Configuring fail2ban"
    cat > /tmp/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
EOF
    
    execute_cmd "sudo mv /tmp/jail.local /etc/fail2ban/jail.local" "Install fail2ban configuration"
    execute_cmd "sudo systemctl restart fail2ban" "Restart fail2ban"
    execute_cmd "sudo systemctl enable fail2ban" "Enable fail2ban"
    
    # Configure AppArmor profiles if enabled
    if [[ "$APPARMOR_ENABLED" == "true" ]]; then
        log_info "Configuring AppArmor profiles"
        execute_cmd "sudo systemctl enable apparmor" "Enable AppArmor"
        execute_cmd "sudo systemctl start apparmor" "Start AppArmor"
        
        # Create basic Docker AppArmor profile
        cat > /tmp/docker-default << 'EOF'
#include <tunables/global>

profile docker-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  network,
  capability,
  file,
  mount,
  
  # Deny dangerous capabilities
  deny capability mac_admin,
  deny capability mac_override,
  deny capability sys_admin,
  deny capability sys_module,
  
  # Allow necessary Docker operations
  capability chown,
  capability dac_override,
  capability fowner,
  capability setgid,
  capability setuid,
  capability net_bind_service,
  
  # Allow access to common directories
  /bin/** rix,
  /usr/bin/** rix,
  /lib/** r,
  /usr/lib/** r,
  /tmp/** rw,
  /var/tmp/** rw,
  
  # Deny access to sensitive files
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /proc/sys/kernel/** w,
  deny /sys/** w,
}
EOF
        
        execute_cmd "sudo mv /tmp/docker-default /etc/apparmor.d/docker-default" "Install Docker AppArmor profile"
        execute_cmd "sudo apparmor_parser -r /etc/apparmor.d/docker-default" "Load Docker AppArmor profile"
        log_success "AppArmor configured and enabled"
    else
        log_info "AppArmor disabled by configuration"
    fi
    
    # Configure system security settings
    log_info "Applying system security settings"
    cat > /tmp/99-security.conf << EOF
# Kernel security settings for COMPASS Stack
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 1
fs.suid_dumpable = 0
EOF
    
    execute_cmd "sudo mv /tmp/99-security.conf /etc/sysctl.d/99-security.conf" "Install security sysctl settings"
    execute_cmd "sudo sysctl --system" "Apply sysctl settings"
    
    # Secure shared memory
    if ! grep -q "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" /etc/fstab; then
        execute_cmd "echo 'tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0' | sudo tee -a /etc/fstab" "Secure shared memory"
    fi
    
    # Configure audit logging if enabled
    if [[ "$AUDIT_LOGGING" == "true" ]]; then
        log_info "Configuring audit logging"
        cat > /tmp/audit.rules << EOF
# COMPASS Stack audit rules
-D
-b 8192
-f 1
-a exit,always -F arch=b64 -S execve -k execve
-a exit,always -F arch=b32 -S execve -k execve
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity
-w /var/log/auth.log -p wa -k logins
-w /var/log/faillog -p wa -k logins
EOF
        
        execute_cmd "sudo mv /tmp/audit.rules /etc/audit/rules.d/audit.rules" "Install audit rules"
        execute_cmd "sudo systemctl restart auditd" "Restart auditd"
        execute_cmd "sudo systemctl enable auditd" "Enable auditd"
        log_success "Audit logging configured and enabled"
    fi
    
    end_section_timer "OS Hardening"
    log_success "Host OS hardening completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 👤 SERVICE USER SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_service_user() {
    log_section "Service User Setup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup service user: $SERVICE_USER"
        return 0
    fi
    
    start_section_timer "User Setup"
    
    # Create service user if it doesn't exist
    if ! id "$SERVICE_USER" &>/dev/null; then
        log_info "Creating service user: $SERVICE_USER"
        execute_cmd "sudo useradd -r -s $SERVICE_SHELL -d /home/$SERVICE_USER -m $SERVICE_USER" "Create service user"
        execute_cmd "sudo usermod -aG docker $SERVICE_USER" "Add user to docker group"
    else
        log_info "Service user $SERVICE_USER already exists"
        # Ensure user is in docker group
        if ! groups "$SERVICE_USER" | grep -q docker; then
            execute_cmd "sudo usermod -aG docker $SERVICE_USER" "Add user to docker group"
        fi
    fi
    
    # Create service group if it doesn't exist
    if ! getent group "$SERVICE_GROUP" &>/dev/null; then
        execute_cmd "sudo groupadd $SERVICE_GROUP" "Create service group"
    fi
    
    # Ensure user is in the service group
    execute_cmd "sudo usermod -aG $SERVICE_GROUP $SERVICE_USER" "Add user to service group"
    
    # Enable systemd linger for the service user (allows user services to run without login)
    execute_cmd "sudo loginctl enable-linger $SERVICE_USER" "Enable systemd linger"
    
    # Create base directory
    execute_cmd "sudo mkdir -p $BASE_DIR" "Create base directory"
    execute_cmd "sudo chown -R $SERVICE_USER:$SERVICE_GROUP $BASE_DIR" "Set base directory ownership"
    execute_cmd "sudo chmod 755 $BASE_DIR" "Set base directory permissions"
    
    # Create subdirectories
    local subdirs=("services" "secrets" "backups" "logs" "ssl" "config")
    for subdir in "${subdirs[@]}"; do
        execute_cmd "sudo -u $SERVICE_USER mkdir -p $BASE_DIR/$subdir" "Create $subdir directory"
    done
    
    # Set up Docker for the service user
    log_info "Configuring Docker for service user"
    execute_cmd "sudo systemctl enable docker" "Enable Docker system service"
    execute_cmd "sudo systemctl start docker" "Start Docker system service"
    
    # Configure Docker daemon for security
    cat > /tmp/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "$CONTAINER_LOG_MAX_SIZE",
    "max-file": "$CONTAINER_LOG_MAX_FILES"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp.json"
}
EOF
    
    execute_cmd "sudo mv /tmp/daemon.json /etc/docker/daemon.json" "Install Docker daemon configuration"
    execute_cmd "sudo systemctl restart docker" "Restart Docker with new configuration"
    
    # Set up user Docker environment
    execute_cmd "sudo -u $SERVICE_USER bash -c 'source ~/.bashrc && systemctl --user enable docker'" "Enable Docker service" || {
        log_info "User Docker service not available, using system Docker"
    }
    
    execute_cmd "sudo -u $SERVICE_USER bash -c 'source ~/.bashrc && systemctl --user start docker'" "Start Docker service" || {
        log_info "User Docker service not available, using system Docker"
    }
    
    end_section_timer "User Setup"
    log_success "Service user setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🐳 DOCKER ENVIRONMENT SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_container_environment() {
    log_section "Container Environment Setup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup container environment"
        return 0
    fi
    
    start_section_timer "Container Environment"
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker"
        execute_cmd "curl -fsSL https://get.docker.com | sudo sh" "Install Docker"
        execute_cmd "sudo systemctl enable docker" "Enable Docker"
        execute_cmd "sudo systemctl start docker" "Start Docker"
    else
        log_info "Docker already installed"
    fi
    
    # Install Docker Compose if not present
    if ! command -v docker-compose &> /dev/null; then
        log_info "Installing Docker Compose"
        local compose_version="v2.24.1"
        execute_cmd "sudo curl -L \"https://github.com/docker/compose/releases/download/$compose_version/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose" "Download Docker Compose"
        execute_cmd "sudo chmod +x /usr/local/bin/docker-compose" "Make Docker Compose executable"
    else
        log_info "Docker Compose already installed"
    fi
    
    # Create Docker networks
    log_info "Setting up Docker networks"
    docker_cmd "docker network create $JARVIS_NETWORK --driver bridge --subnet=172.20.0.0/16 --gateway=172.20.0.1 || true" "Create main network"
    docker_cmd "docker network create $PUBLIC_TIER --driver bridge --subnet=172.21.0.0/16 --gateway=172.21.0.1 || true" "Create public tier network"
    docker_cmd "docker network create $PRIVATE_TIER --driver bridge --subnet=172.22.0.0/16 --gateway=172.22.0.1 || true" "Create private tier network"
    
    # Set up container security profiles if enabled
    if [[ "$APPARMOR_ENABLED" == "true" ]]; then
        log_info "Configuring container security profiles"
        
        # Create AppArmor profile for containers
        cat > /tmp/docker-jarvis << 'EOF'
#include <tunables/global>

profile docker-jarvis flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  
  network inet tcp,
  network inet udp,
  capability,
  file,
  mount,
  
  # Deny dangerous capabilities
  deny capability mac_admin,
  deny capability mac_override,
  deny capability sys_admin,
  deny capability sys_module,
  deny capability sys_rawio,
  
  # Allow necessary capabilities
  capability chown,
  capability dac_override,
  capability fowner,
  capability setgid,
  capability setuid,
  capability net_bind_service,
  
  # Allow container filesystem access
  /bin/** rix,
  /usr/bin/** rix,
  /lib/** r,
  /usr/lib/** r,
  /etc/** r,
  /tmp/** rw,
  /var/tmp/** rw,
  /var/log/** rw,
  
  # Allow application-specific paths
  /app/** rw,
  /data/** rw,
  /config/** rw,
  
  # Deny sensitive host paths
  deny /proc/sys/kernel/** w,
  deny /sys/** w,
  deny /dev/** w,
  deny /host/** rw,
}
EOF
        
        execute_cmd "sudo mv /tmp/docker-jarvis /etc/apparmor.d/docker-jarvis" "Install container AppArmor profile"
        execute_cmd "sudo apparmor_parser -r /etc/apparmor.d/docker-jarvis" "Load container AppArmor profile"
    fi
    
    # Configure Docker security options
    log_info "Applying Docker security configuration"
    
    # Create seccomp profile for enhanced security
    cat > /tmp/seccomp.json << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "accept", "accept4", "access", "adjtimex", "alarm", "bind", "brk", "capget", "capset",
        "chdir", "chmod", "chown", "chown32", "clock_adjtime", "clock_getres", "clock_gettime",
        "clock_nanosleep", "close", "connect", "copy_file_range", "creat", "dup", "dup2", "dup3",
        "epoll_create", "epoll_create1", "epoll_ctl", "epoll_ctl_old", "epoll_pwait", "epoll_wait",
        "eventfd", "eventfd2", "execve", "execveat", "exit", "exit_group", "faccessat", "fadvise64",
        "fallocate", "fanotify_mark", "fchdir", "fchmod", "fchmodat", "fchown", "fchown32", "fchownat",
        "fcntl", "fcntl64", "fdatasync", "fgetxattr", "flistxattr", "flock", "fork", "fremovexattr",
        "fsetxattr", "fstat", "fstat64", "fstatat64", "fstatfs", "fstatfs64", "fsync", "ftruncate",
        "ftruncate64", "futex", "getcwd", "getdents", "getdents64", "getegid", "getegid32", "geteuid",
        "geteuid32", "getgid", "getgid32", "getgroups", "getgroups32", "getitimer", "getpgrp",
        "getpid", "getppid", "getpriority", "getrandom", "getresgid", "getresgid32", "getresuid",
        "getresuid32", "getrlimit", "get_robust_list", "getrusage", "getsid", "getsockname",
        "getsockopt", "get_thread_area", "gettid", "gettimeofday", "getuid", "getuid32", "getxattr",
        "inotify_add_watch", "inotify_init", "inotify_init1", "inotify_rm_watch", "io_cancel",
        "ioctl", "io_destroy", "io_getevents", "ioprio_get", "ioprio_set", "io_setup", "io_submit",
        "ipc", "kill", "lgetxattr", "link", "linkat", "listen", "listxattr", "llistxattr",
        "lremovexattr", "lseek", "lsetxattr", "lstat", "lstat64", "madvise", "memfd_create",
        "mincore", "mkdir", "mkdirat", "mknod", "mknodat", "mlock", "mlock2", "mlockall", "mmap",
        "mmap2", "mprotect", "mq_getsetattr", "mq_notify", "mq_open", "mq_timedreceive",
        "mq_timedsend", "mq_unlink", "mremap", "msgctl", "msgget", "msgrcv", "msgsnd", "msync",
        "munlock", "munlockall", "munmap", "nanosleep", "newfstatat", "open", "openat", "pause",
        "pipe", "pipe2", "poll", "ppoll", "prctl", "pread64", "preadv", "prlimit64", "pselect6",
        "ptrace", "pwrite64", "pwritev", "read", "readahead", "readlink", "readlinkat", "readv",
        "recv", "recvfrom", "recvmmsg", "recvmsg", "remap_file_pages", "removexattr", "rename",
        "renameat", "renameat2", "restart_syscall", "rmdir", "rt_sigaction", "rt_sigpending",
        "rt_sigprocmask", "rt_sigqueueinfo", "rt_sigreturn", "rt_sigsuspend", "rt_sigtimedwait",
        "rt_tgsigqueueinfo", "sched_getaffinity", "sched_getattr", "sched_getparam", "sched_get_priority_max",
        "sched_get_priority_min", "sched_getscheduler", "sched_rr_get_interval", "sched_setaffinity",
        "sched_setattr", "sched_setparam", "sched_setscheduler", "sched_yield", "seccomp", "select",
        "semctl", "semget", "semop", "semtimedop", "send", "sendfile", "sendfile64", "sendmmsg",
        "sendmsg", "sendto", "setfsgid", "setfsgid32", "setfsuid", "setfsuid32", "setgid", "setgid32",
        "setgroups", "setgroups32", "setitimer", "setpgid", "setpriority", "setregid", "setregid32",
        "setresgid", "setresgid32", "setresuid", "setresuid32", "setreuid", "setreuid32", "setrlimit",
        "set_robust_list", "setsid", "setsockopt", "set_thread_area", "set_tid_address", "setuid",
        "setuid32", "setxattr", "shmat", "shmctl", "shmdt", "shmget", "shutdown", "sigaltstack",
        "signalfd", "signalfd4", "sigpending", "sigprocmask", "sigreturn", "socket", "socketcall",
        "socketpair", "splice", "stat", "stat64", "statfs", "statfs64", "statx", "symlink",
        "symlinkat", "sync", "sync_file_range", "syncfs", "sysinfo", "tee", "tgkill", "time",
        "timer_create", "timer_delete", "timerfd_create", "timerfd_gettime", "timerfd_settime",
        "timer_getoverrun", "timer_gettime", "timer_settime", "times", "tkill", "truncate",
        "truncate64", "ugetrlimit", "umask", "uname", "unlink", "unlinkat", "utime", "utimensat",
        "utimes", "vfork", "vhangup", "vmsplice", "wait4", "waitid", "waitpid", "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
    
    execute_cmd "sudo mv /tmp/seccomp.json /etc/docker/seccomp.json" "Install Docker seccomp profile"
    execute_cmd "sudo systemctl restart docker" "Restart Docker with security configuration"
    
    end_section_timer "Container Environment"
    log_success "Container environment setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 TIMEZONE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

setup_system_timezone() {
    log_section "Configuring System Timezone"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure timezone to: $N8N_TIMEZONE"
        return 0
    fi
    
    # Validate timezone format
    if [ -z "$N8N_TIMEZONE" ]; then
        log_info "Using America/Los_Angeles timezone (default)"
        local target_timezone="America/Los_Angeles"
    else
        local target_timezone="$N8N_TIMEZONE"
        log_info "Setting system timezone to: $target_timezone"
    fi
    
    # Get current timezone
    local current_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
    log_info "Current timezone: $current_timezone"
    
    # Set timezone if different
    if [[ "$current_timezone" != "$target_timezone" ]]; then
        if execute_cmd "sudo timedatectl set-timezone $target_timezone" "Set system timezone"; then
            # Verify the change
            local new_timezone=$(timedatectl show --property=Timezone --value 2>/dev/null)
            if [[ "$new_timezone" == "$target_timezone" ]]; then
                log_success "System timezone set to: $new_timezone"
            else
                log_error "Failed to verify timezone change"
                return 1
            fi
        else
            log_error "Failed to set timezone to $target_timezone"
            return 1
        fi
    else
        log_info "Timezone already set correctly"
    fi
    
    # Display current time information
    log_info "Current system time: $(date)"
    log_info "UTC time: $(date -u)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️ COMPLIANCE MONITORING SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_compliance_monitoring() {
    log_section "Compliance Monitoring Setup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup compliance monitoring system"
        return 0
    fi
    
    # Check if compliance monitoring is enabled
    if [[ "${COMPLIANCE_MONITORING_ENABLED:-true}" != "true" ]]; then
        log_info "Compliance monitoring disabled by configuration - skipping"
        return 0
    fi
    
    start_section_timer "Compliance Setup"
    
    # Install jq if not present (required for site registry management)
    if ! command -v jq &> /dev/null; then
        log_info "Installing jq for JSON processing"
        execute_cmd "sudo apt-get update -y" "Update package lists for jq"
        execute_cmd "sudo apt-get install -y jq" "Install jq JSON processor"
    else
        log_info "jq already installed"
    fi
    
    # Setup compliance monitoring system
    log_info "Initializing compliance monitoring system"
    if bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" setup; then
        log_success "Compliance monitoring system initialized"
    else
        log_warning "Compliance monitoring setup encountered issues - continuing installation"
        # Don't fail the entire setup if compliance setup has issues
    fi
    
    # Generate initial compliance documentation if auto-update is enabled
    if [[ "${AUTO_UPDATE_DOCS:-true}" == "true" ]]; then
        log_info "Generating initial compliance documentation"
        if bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" generate-docs; then
            log_success "Initial compliance documentation generated"
        else
            log_warning "Failed to generate initial compliance documentation"
        fi
    fi
    
    # Initialize site registry with primary domain if configured
    if [[ -n "${DOMAIN:-}" ]] && [[ "$DOMAIN" != "test.example.com" ]]; then
        log_info "Registering primary domain in site registry: $DOMAIN"
        
        # Source common.sh to get site registry functions
        source "${PROJECT_ROOT}/scripts/lib/common.sh"
        
        if add_site_to_registry "$DOMAIN" "${DEFAULT_COMPLIANCE_PROFILE:-default}"; then
            log_success "Primary domain registered in site registry"
            
            # Update compliance documentation for the new site
            if [[ "${AUTO_UPDATE_DOCS:-true}" == "true" ]]; then
                if bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" update-site-docs add "$DOMAIN"; then
                    log_success "Compliance documentation updated for primary domain"
                else
                    log_warning "Failed to update compliance documentation for primary domain"
                fi
            fi
        else
            log_warning "Failed to register primary domain in site registry"
        fi
    else
        log_info "No domain configured or using default - skipping site registry"
    fi
    
    # Set up compliance monitoring cron job if enabled and not in container
    if [[ "${COMPLIANCE_MONITORING_ENABLED:-true}" == "true" ]] && [[ ! -f /.dockerenv ]]; then
        log_info "Setting up compliance monitoring cron job"
        
        local cron_schedule="${COMPLIANCE_REPORT_SCHEDULE:-0 2 * * 0}"
        local cron_job="$cron_schedule cd ${PROJECT_ROOT} && bash scripts/security/compliance_monitoring.sh regenerate-reports >> /var/log/compliance-monitoring.log 2>&1"
        
        # Add cron job for jarvis user
        if sudo -u "$SERVICE_USER" crontab -l 2>/dev/null | grep -q "compliance_monitoring.sh"; then
            log_info "Compliance monitoring cron job already exists"
        else
            (sudo -u "$SERVICE_USER" crontab -l 2>/dev/null || true; echo "$cron_job") | sudo -u "$SERVICE_USER" crontab -
            log_success "Compliance monitoring cron job added"
        fi
    fi
    
    end_section_timer "Compliance Setup"
    log_success "Compliance monitoring setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN SETUP ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Main setup function
run_setup() {
    log_section "COMPASS Stack System Setup"
    
    # Initialize timing
    init_timing_system
    
    # Run setup phases
    if validate_environment && \
       validate_user_configuration && \
       check_prerequisites && \
       harden_host_os && \
       setup_service_user && \
       setup_container_environment && \
       setup_compliance_monitoring && \
       setup_system_timezone; then
        
        log_success "System setup completed successfully"
        return 0
    else
        log_error "System setup failed"
        return 1
    fi
}

# Main function for testing
main() {
    case "${1:-setup}" in
        "setup"|"run")
            run_setup
            ;;
        "harden")
            harden_host_os
            ;;
        "user")
            setup_service_user
            ;;
        "docker")
            setup_container_environment
            ;;
        "compliance")
            setup_compliance_monitoring
            ;;
        "timezone")
            setup_system_timezone
            ;;
        "validate")
            validate_environment && validate_user_configuration && check_prerequisites
            ;;
        *)
            echo "Usage: $0 [setup|harden|user|docker|compliance|timezone|validate]"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi