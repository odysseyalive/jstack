#!/bin/bash
# Docker daemon.json repair and security configuration
# Handles backup, validation, and secure deployment of Docker daemon configuration

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
# 🐳 DOCKER DAEMON CONFIGURATION REPAIR
# ═══════════════════════════════════════════════════════════════════════════════

# Docker daemon configuration paths
DAEMON_JSON_PATH="/etc/docker/daemon.json"
BACKUP_DIR="/etc/docker/backups"
CORRECTED_CONFIG_PATH="${PROJECT_ROOT}/.claude/temp/daemon.json.corrected"
TEMP_CONFIG_PATH="/tmp/daemon.json.temp"

backup_current_daemon_config() {
    log_section "Backing up current Docker daemon configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would backup current daemon.json"
        return 0
    fi
    
    # Create backup directory
    if ! execute_cmd "sudo mkdir -p ${BACKUP_DIR}" "Create backup directory"; then
        log_error "Failed to create backup directory"
        return 1
    fi
    
    # Create timestamped backup
    local backup_file="${BACKUP_DIR}/daemon.json.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$DAEMON_JSON_PATH" ]]; then
        if execute_cmd "sudo cp ${DAEMON_JSON_PATH} ${backup_file}" "Backup current daemon.json"; then
            log_success "Current daemon.json backed up to: $backup_file"
            export DAEMON_BACKUP_PATH="$backup_file"
            return 0
        else
            log_error "Failed to create backup of daemon.json"
            return 1
        fi
    else
        log_warning "No existing daemon.json found, creating new configuration"
        return 0
    fi
}

validate_daemon_config() {
    local config_file="$1"
    log_info "Validating Docker daemon configuration: $config_file"
    
    # Basic JSON syntax validation
    if ! jq empty "$config_file" 2>/dev/null; then
        log_error "Invalid JSON syntax in daemon configuration"
        return 1
    fi
    
    # Semantic validation - check required security fields
    local required_fields=("no-new-privileges" "seccomp-profile")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".\"$field\"" "$config_file" >/dev/null 2>&1; then
            log_warning "Missing security field: $field"
        fi
    done
    
    # Check for nvidia runtime preservation
    if jq -e '.runtimes.nvidia' "$config_file" >/dev/null 2>&1; then
        log_success "Nvidia runtime configuration preserved"
    else
        log_warning "Nvidia runtime not found in configuration"
    fi
    
    log_success "Daemon configuration validation completed"
    return 0
}

create_seccomp_profile() {
    log_info "Creating Docker seccomp security profile"
    
    local seccomp_path="/etc/docker/seccomp.json"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create seccomp profile at $seccomp_path"
        return 0
    fi
    
    # Create minimal seccomp profile if it doesn't exist
    if [[ ! -f "$seccomp_path" ]]; then
        local seccomp_content='{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": [
        "accept",
        "accept4",
        "access",
        "adjtimex",
        "alarm",
        "bind",
        "brk",
        "capget",
        "capset",
        "chdir",
        "chmod",
        "chown",
        "chroot",
        "clock_getres",
        "clock_gettime",
        "clock_nanosleep",
        "close",
        "connect",
        "copy_file_range",
        "creat",
        "dup",
        "dup2",
        "dup3",
        "epoll_create",
        "epoll_create1",
        "epoll_ctl",
        "epoll_pwait",
        "epoll_wait",
        "eventfd",
        "eventfd2",
        "execve",
        "execveat",
        "exit",
        "exit_group",
        "faccessat",
        "fadvise64",
        "fallocate",
        "fanotify_mark",
        "fchdir",
        "fchmod",
        "fchmodat",
        "fchown",
        "fchownat",
        "fcntl",
        "fdatasync",
        "fgetxattr",
        "flistxattr",
        "flock",
        "fork",
        "fremovexattr",
        "fsetxattr",
        "fstat",
        "fstatfs",
        "fsync",
        "ftruncate",
        "futex",
        "getcpu",
        "getcwd",
        "getdents",
        "getdents64",
        "getegid",
        "geteuid",
        "getgid",
        "getgroups",
        "getitimer",
        "getpeername",
        "getpgid",
        "getpgrp",
        "getpid",
        "getppid",
        "getpriority",
        "getrandom",
        "getresgid",
        "getresuid",
        "getrlimit",
        "get_robust_list",
        "getrusage",
        "getsid",
        "getsockname",
        "getsockopt",
        "get_thread_area",
        "gettid",
        "gettimeofday",
        "getuid",
        "getxattr",
        "inotify_add_watch",
        "inotify_init",
        "inotify_init1",
        "inotify_rm_watch",
        "io_cancel",
        "ioctl",
        "io_destroy",
        "io_getevents",
        "ioprio_get",
        "ioprio_set",
        "io_setup",
        "io_submit",
        "ipc",
        "kill",
        "lchown",
        "lgetxattr",
        "link",
        "linkat",
        "listen",
        "listxattr",
        "llistxattr",
        "lremovexattr",
        "lseek",
        "lsetxattr",
        "lstat",
        "madvise",
        "memfd_create",
        "mincore",
        "mkdir",
        "mkdirat",
        "mknod",
        "mknodat",
        "mlock",
        "mlock2",
        "mlockall",
        "mmap",
        "mount",
        "mprotect",
        "mq_getsetattr",
        "mq_notify",
        "mq_open",
        "mq_timedreceive",
        "mq_timedsend",
        "mq_unlink",
        "mremap",
        "msgctl",
        "msgget",
        "msgrcv",
        "msgsnd",
        "msync",
        "munlock",
        "munlockall",
        "munmap",
        "nanosleep",
        "newfstatat",
        "open",
        "openat",
        "pause",
        "pipe",
        "pipe2",
        "poll",
        "ppoll",
        "prctl",
        "pread64",
        "prlimit64",
        "pselect6",
        "ptrace",
        "pwrite64",
        "read",
        "readahead",
        "readlink",
        "readlinkat",
        "readv",
        "recv",
        "recvfrom",
        "recvmmsg",
        "recvmsg",
        "remap_file_pages",
        "removexattr",
        "rename",
        "renameat",
        "renameat2",
        "restart_syscall",
        "rmdir",
        "rt_sigaction",
        "rt_sigpending",
        "rt_sigprocmask",
        "rt_sigqueueinfo",
        "rt_sigreturn",
        "rt_sigsuspend",
        "rt_sigtimedwait",
        "rt_tgsigqueueinfo",
        "sched_getaffinity",
        "sched_getattr",
        "sched_getparam",
        "sched_get_priority_max",
        "sched_get_priority_min",
        "sched_getscheduler",
        "sched_rr_get_interval",
        "sched_setaffinity",
        "sched_setattr",
        "sched_setparam",
        "sched_setscheduler",
        "sched_yield",
        "seccomp",
        "select",
        "semctl",
        "semget",
        "semop",
        "semtimedop",
        "send",
        "sendfile",
        "sendmmsg",
        "sendmsg",
        "sendto",
        "setfsgid",
        "setfsuid",
        "setgid",
        "setgroups",
        "setitimer",
        "setpgid",
        "setpriority",
        "setregid",
        "setresgid",
        "setresuid",
        "setreuid",
        "setrlimit",
        "set_robust_list",
        "setsid",
        "setsockopt",
        "set_thread_area",
        "set_tid_address",
        "setuid",
        "setxattr",
        "shmat",
        "shmctl",
        "shmdt",
        "shmget",
        "shutdown",
        "sigaltstack",
        "signalfd",
        "signalfd4",
        "sigreturn",
        "socket",
        "socketcall",
        "socketpair",
        "splice",
        "stat",
        "statfs",
        "symlink",
        "symlinkat",
        "sync",
        "sync_file_range",
        "syncfs",
        "sysinfo",
        "tee",
        "tgkill",
        "time",
        "timer_create",
        "timer_delete",
        "timer_getoverrun",
        "timer_gettime",
        "timer_settime",
        "times",
        "tkill",
        "truncate",
        "umask",
        "uname",
        "unlink",
        "unlinkat",
        "utime",
        "utimensat",
        "utimes",
        "vfork",
        "vmsplice",
        "wait4",
        "waitid",
        "write",
        "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}'
        
        if echo "$seccomp_content" | sudo tee "$seccomp_path" > /dev/null; then
            log_success "Created Docker seccomp security profile"
            execute_cmd "sudo chown root:root ${seccomp_path}" "Set seccomp profile ownership"
            execute_cmd "sudo chmod 644 ${seccomp_path}" "Set seccomp profile permissions"
        else
            log_error "Failed to create seccomp profile"
            return 1
        fi
    else
        log_success "Docker seccomp profile already exists"
    fi
    
    return 0
}

deploy_daemon_config() {
    log_section "Deploying Docker daemon security configuration"
    
    if [[ ! -f "$CORRECTED_CONFIG_PATH" ]]; then
        log_error "Corrected daemon configuration not found: $CORRECTED_CONFIG_PATH"
        return 1
    fi
    
    # Validate corrected configuration
    if ! validate_daemon_config "$CORRECTED_CONFIG_PATH"; then
        log_error "Corrected configuration validation failed"
        return 1
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would deploy corrected daemon.json configuration"
        log_info "[DRY-RUN] Configuration content:"
        cat "$CORRECTED_CONFIG_PATH"
        return 0
    fi
    
    # Create seccomp profile first
    if ! create_seccomp_profile; then
        log_error "Failed to create seccomp profile"
        return 1
    fi
    
    # Copy corrected configuration to temporary location
    if ! cp "$CORRECTED_CONFIG_PATH" "$TEMP_CONFIG_PATH"; then
        log_error "Failed to copy corrected configuration to temporary location"
        return 1
    fi
    
    # Deploy the configuration
    if execute_cmd "sudo cp ${TEMP_CONFIG_PATH} ${DAEMON_JSON_PATH}" "Deploy corrected daemon.json"; then
        execute_cmd "sudo chown root:root ${DAEMON_JSON_PATH}" "Set daemon.json ownership"
        execute_cmd "sudo chmod 644 ${DAEMON_JSON_PATH}" "Set daemon.json permissions"
        log_success "Docker daemon configuration deployed successfully"
        
        # Clean up temporary file
        rm -f "$TEMP_CONFIG_PATH"
        return 0
    else
        log_error "Failed to deploy Docker daemon configuration"
        return 1
    fi
}

restart_docker_service() {
    log_section "Restarting Docker service with new configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would restart Docker service"
        return 0
    fi
    
    # Validate configuration before restart
    log_info "Validating deployed configuration"
    if ! validate_daemon_config "$DAEMON_JSON_PATH"; then
        log_error "Configuration validation failed before restart"
        return 1
    fi
    
    # Stop Docker service gracefully
    log_info "Stopping Docker service"
    if ! execute_cmd "sudo systemctl stop docker" "Stop Docker service"; then
        log_warning "Failed to stop Docker service gracefully, attempting force stop"
        execute_cmd "sudo systemctl kill docker" "Force stop Docker service"
    fi
    
    # Start Docker service
    log_info "Starting Docker service with new configuration"
    if execute_cmd "sudo systemctl start docker" "Start Docker service"; then
        # Wait for service to be ready
        sleep 3
        
        # Check service status
        if execute_cmd "sudo systemctl is-active docker" "Check Docker service status"; then
            log_success "Docker service restarted successfully"
            return 0
        else
            log_error "Docker service failed to start properly"
            return 1
        fi
    else
        log_error "Failed to start Docker service"
        return 1
    fi
}

verify_docker_functionality() {
    log_section "Verifying Docker functionality and security compliance"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would verify Docker functionality"
        return 0
    fi
    
    # Check Docker version and info
    log_info "Checking Docker version and configuration"
    if execute_cmd "docker version" "Check Docker version"; then
        log_success "Docker version check passed"
    else
        log_error "Docker version check failed"
        return 1
    fi
    
    # Check Docker daemon configuration
    log_info "Verifying daemon configuration is loaded"
    if docker info --format '{{json .}}' | jq -e '.SecurityOptions[] | select(contains("seccomp"))' >/dev/null 2>&1; then
        log_success "Seccomp security profile is active"
    else
        log_warning "Seccomp security profile not detected in Docker info"
    fi
    
    # Test basic Docker functionality with security constraints
    log_info "Testing basic Docker functionality"
    if execute_cmd "docker run --rm hello-world" "Test Docker container execution"; then
        log_success "Docker container execution test passed"
    else
        log_error "Docker container execution test failed"
        return 1
    fi
    
    # Verify nvidia runtime if available
    if docker info --format '{{json .Runtimes}}' | jq -e '.nvidia' >/dev/null 2>&1; then
        log_success "Nvidia runtime is available and configured"
    else
        log_info "Nvidia runtime not configured (this may be expected)"
    fi
    
    log_success "Docker functionality verification completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN EXECUTION FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

repair_docker_daemon() {
    log_section "Docker Daemon Configuration Repair"
    
    # Initialize logging
    setup_logging
    
    # Step 1: Backup current configuration
    if ! backup_current_daemon_config; then
        log_error "Configuration backup failed"
        return 1
    fi
    
    # Step 2: Deploy corrected configuration with security hardening
    if ! deploy_daemon_config; then
        log_error "Configuration deployment failed"
        return 1
    fi
    
    # Step 3: Restart Docker service
    if ! restart_docker_service; then
        log_error "Docker service restart failed"
        
        # Attempt to restore from backup if available
        if [[ -n "${DAEMON_BACKUP_PATH:-}" && -f "$DAEMON_BACKUP_PATH" ]]; then
            log_warning "Attempting to restore from backup"
            if execute_cmd "sudo cp ${DAEMON_BACKUP_PATH} ${DAEMON_JSON_PATH}" "Restore from backup"; then
                execute_cmd "sudo systemctl start docker" "Restart Docker with backup config"
                log_warning "Restored from backup due to configuration failure"
            fi
        fi
        return 1
    fi
    
    # Step 4: Verify functionality and security compliance
    if ! verify_docker_functionality; then
        log_error "Docker functionality verification failed"
        return 1
    fi
    
    log_success "Docker daemon configuration repair completed successfully"
    log_info "Configuration backup available at: ${DAEMON_BACKUP_PATH:-N/A}"
    log_info "New configuration deployed with security hardening"
    
    return 0
}

# Execute repair if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    repair_docker_daemon "$@"
fi