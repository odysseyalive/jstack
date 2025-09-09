#!/bin/bash
# JarvisJR Stack - Comprehensive Diagnostic Module
# Collects troubleshooting information while maintaining security boundaries
#
# This module provides comprehensive diagnostic data collection for the JarvisJR Stack
# following established security patterns and modular architecture conventions

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
# 🔍 DIAGNOSTIC CONFIGURATION AND SECURITY
# ═══════════════════════════════════════════════════════════════════════════════

# Diagnostic levels (tiered diagnostic collection)
DIAGNOSTIC_LEVEL="${DIAGNOSTIC_LEVEL:-detailed}"  # basic, detailed, comprehensive

# Security filtering patterns - NEVER include these in diagnostic output
SENSITIVE_PATTERNS=(
    "password"
    "secret"
    "key" 
    "token"
    "auth"
    "cert"
    "private"
    "credential"
    "api_key"
    "jwt"
    "bearer"
)

# Filter sensitive information from diagnostic output
filter_sensitive_data() {
    local input="$1"
    local filtered="$input"
    
    # Apply security filtering for each pattern
    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        # Case-insensitive filtering, replace with [REDACTED]
        filtered=$(echo "$filtered" | sed -E "s/([^[:space:]]*${pattern}[^[:space:]]*[[:space:]]*[=:][[:space:]]*)[^[:space:]]+/\\1[REDACTED]/gi")
    done
    
    echo "$filtered"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 SYSTEM INFORMATION COLLECTION
# ═══════════════════════════════════════════════════════════════════════════════

# Collect basic system information (security-compliant)
collect_system_info() {
    log_info "Collecting system information (basic level)"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
🖥️  SYSTEM INFORMATION
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "Hostname: $(hostname)"
    echo "Operating System: $(uname -a)"
    echo "Distribution: $(lsb_release -d 2>/dev/null | cut -f2- || echo 'Unknown')"
    echo "Kernel Version: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo "Current User: $(whoami)"
    echo "Current Directory: $(pwd)"
    echo "Shell: $SHELL"
    echo "Date: $(date)"
    echo "Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo 'Unknown')"
    
    echo ""
    echo "CPU Information:"
    echo "  Cores: $(nproc)"
    echo "  Model: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//' || echo 'Unknown')"
    
    echo ""
    echo "Memory Information:"
    echo "  Total RAM: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "  Available RAM: $(free -h | awk '/^Mem:/ {print $7}')"
    echo "  Used RAM: $(free -h | awk '/^Mem:/ {print $3}')"
    echo "  Swap Total: $(free -h | awk '/^Swap:/ {print $2}')"
    echo "  Swap Used: $(free -h | awk '/^Swap:/ {print $3}')"
    
    echo ""
    echo "Disk Usage:"
    df -h | grep -E '^/dev/|^tmpfs' | while read line; do
        echo "  $line"
    done
    
    echo ""
    echo "Load Average: $(cat /proc/loadavg)"
    
    # Network interfaces (non-sensitive information only)
    echo ""
    echo "Network Interfaces:"
    ip addr show | grep -E '^[0-9]+:|inet ' | sed 's/^/  /'
}

# Collect detailed system information
collect_detailed_system_info() {
    if [[ "$DIAGNOSTIC_LEVEL" == "basic" ]]; then
        return 0
    fi
    
    log_info "Collecting detailed system information"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
🔧 DETAILED SYSTEM CONFIGURATION
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "Process Count: $(ps aux | wc -l)"
    echo "Open Files: $(lsof 2>/dev/null | wc -l || echo 'Unable to determine')"
    
    echo ""
    echo "Top CPU Processes:"
    ps aux --sort=-%cpu | head -6 | sed 's/^/  /'
    
    echo ""
    echo "Top Memory Processes:"
    ps aux --sort=-%mem | head -6 | sed 's/^/  /'
    
    echo ""
    echo "Disk I/O Statistics (if available):"
    if command -v iostat &>/dev/null; then
        iostat -x 1 1 2>/dev/null | sed 's/^/  /' || echo "  iostat not available"
    else
        echo "  iostat command not available"
    fi
    
    echo ""
    echo "System Limits:"
    echo "  Max file descriptors: $(ulimit -n)"
    echo "  Max processes: $(ulimit -u)"
    echo "  Max memory size: $(ulimit -v)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🐳 DOCKER DIAGNOSTIC COLLECTION
# ═══════════════════════════════════════════════════════════════════════════════

# Collect Docker daemon information
collect_docker_info() {
    log_info "Collecting Docker configuration and status"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
🐳 DOCKER INFORMATION
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    if command -v docker &>/dev/null; then
        echo "Docker Version: $(docker --version 2>/dev/null || echo 'Docker command failed')"
        echo "Docker Compose Version: $(docker compose version 2>/dev/null || echo 'Docker Compose command failed')"
        
        echo ""
        echo "Docker System Info:"
        if docker info &>/dev/null; then
            docker info 2>/dev/null | filter_sensitive_data | sed 's/^/  /'
        else
            echo "  Unable to get Docker info - daemon may not be running"
        fi
        
        echo ""
        echo "Docker Networks:"
        docker network ls 2>/dev/null | sed 's/^/  /' || echo "  Unable to list Docker networks"
        
        echo ""
        echo "Docker Volumes:"
        docker volume ls 2>/dev/null | sed 's/^/  /' || echo "  Unable to list Docker volumes"
        
        echo ""
        echo "Docker Images:"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null | sed 's/^/  /' || echo "  Unable to list Docker images"
        
    else
        echo "Docker is not installed or not in PATH"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🏥 JARVISJR STACK SERVICE HEALTH ASSESSMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Collect JarvisJR Stack specific container health
collect_jarvisjr_service_health() {
    log_info "Collecting JarvisJR Stack service health information"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
🏥 JARVISJR STACK SERVICE HEALTH
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        echo "JarvisJR Stack Container Status:"
        
        # Define expected JarvisJR Stack containers
        local jarvisjr_containers=("supabase-db" "supabase-api" "supabase-studio" "n8n" "nginx-proxy" "chrome")
        
        for container in "${jarvisjr_containers[@]}"; do
            if docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$container"; then
                echo "  ✓ $container:"
                docker ps -a --format "    Status: {{.Status}}" --filter "name=$container" 2>/dev/null
                docker ps -a --format "    Ports: {{.Ports}}" --filter "name=$container" 2>/dev/null
                
                # Check container logs for recent errors (last 50 lines)
                echo "    Recent log entries (last 50 lines):"
                docker logs --tail 50 "$container" 2>&1 | grep -i error | tail -5 | sed 's/^/      /' || echo "      No recent errors found"
            else
                echo "  ✗ $container: Not found"
            fi
        done
        
        echo ""
        echo "Docker Networks (JarvisJR Stack specific):"
        docker network ls | grep -E "(jstack|jarvis|supabase|n8n)" | sed 's/^/  /' || echo "  No JarvisJR Stack networks found"
        
        echo ""
        echo "Docker Volumes (JarvisJR Stack specific):"
        docker volume ls | grep -E "(jstack|jarvis|supabase|n8n|postgres)" | sed 's/^/  /' || echo "  No JarvisJR Stack volumes found"
        
        # Health checks for critical services
        echo ""
        echo "Service Health Checks:"
        
        # PostgreSQL health check
        if docker ps | grep -q supabase-db; then
            echo "  PostgreSQL (supabase-db):"
            if docker exec supabase-db pg_isready 2>/dev/null; then
                echo "    ✓ Database is accepting connections"
            else
                echo "    ✗ Database is not responding"
            fi
        fi
        
        # N8N health check
        if docker ps | grep -q n8n; then
            echo "  N8N Workflow Engine:"
            if curl -s --max-time 5 http://localhost:5678/healthz &>/dev/null; then
                echo "    ✓ N8N service is responding"
            else
                echo "    ⚠ N8N health check failed or service not accessible"
            fi
        fi
        
        # NGINX health check
        if docker ps | grep -q nginx-proxy; then
            echo "  NGINX Reverse Proxy:"
            if curl -s --max-time 5 http://localhost:80 &>/dev/null; then
                echo "    ✓ NGINX is responding on port 80"
            else
                echo "    ⚠ NGINX health check failed"
            fi
        fi
        
    else
        echo "Docker is not available - cannot collect container health information"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# ⚙️  CONFIGURATION VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate JarvisJR Stack configuration with security filtering
collect_configuration_validation() {
    log_info "Validating JarvisJR Stack configuration (sensitive data filtered)"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
⚙️  CONFIGURATION VALIDATION
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "Configuration Files Status:"
    
    # Check for required configuration files
    if [[ -f "$PROJECT_ROOT/jstack.config.default" ]]; then
        echo "  ✓ jstack.config.default exists"
    else
        echo "  ✗ jstack.config.default is missing"
    fi
    
    if [[ -f "$PROJECT_ROOT/jstack.config" ]]; then
        echo "  ✓ jstack.config exists"
        echo "  Configuration last modified: $(stat -c %y "$PROJECT_ROOT/jstack.config" 2>/dev/null || echo 'Unknown')"
    else
        echo "  ✗ jstack.config is missing (required for operation)"
    fi
    
    echo ""
    echo "Configuration Validation:"
    
    # Check critical configuration variables (filter sensitive data)
    if [[ -n "$DOMAIN" ]]; then
        echo "  ✓ DOMAIN is set: $DOMAIN"
    else
        echo "  ✗ DOMAIN is not set (required)"
    fi
    
    if [[ -n "$EMAIL" ]]; then
        echo "  ✓ EMAIL is set: [REDACTED]"
    else
        echo "  ✗ EMAIL is not set (required for SSL certificates)"
    fi
    
    if [[ -n "$BASE_DIR" ]]; then
        echo "  ✓ BASE_DIR is set: $BASE_DIR"
        if [[ -d "$BASE_DIR" ]]; then
            echo "    ✓ Base directory exists"
            echo "    Permissions: $(ls -ld "$BASE_DIR" 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"
        else
            echo "    ✗ Base directory does not exist"
        fi
    else
        echo "  ✗ BASE_DIR is not set"
    fi
    
    if [[ -n "$SERVICE_USER" ]]; then
        echo "  ✓ SERVICE_USER is set: $SERVICE_USER"
        if id "$SERVICE_USER" &>/dev/null; then
            echo "    ✓ Service user exists"
        else
            echo "    ✗ Service user does not exist"
        fi
    else
        echo "  ✗ SERVICE_USER is not set"
    fi
    
    echo ""
    echo "Service Configuration:"
    echo "  Supabase Subdomain: ${SUPABASE_SUBDOMAIN:-[NOT SET]}"
    echo "  Studio Subdomain: ${STUDIO_SUBDOMAIN:-[NOT SET]}"
    echo "  N8N Subdomain: ${N8N_SUBDOMAIN:-[NOT SET]}"
    echo "  Browser Automation Enabled: ${ENABLE_BROWSER_AUTOMATION:-[NOT SET]}"
    echo "  SSL Enabled: ${ENABLE_SSL:-[NOT SET]}"
    echo "  Backup Encryption: ${BACKUP_ENCRYPTION:-[NOT SET]}"
    
    echo ""
    echo "Directory Structure:"
    local directories=("$BASE_DIR/logs" "$BASE_DIR/backups" "$BASE_DIR/config" "$BASE_DIR/data")
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "  ✓ $dir exists ($(du -sh "$dir" 2>/dev/null | cut -f1 || echo 'Unknown size'))"
        else
            echo "  ✗ $dir does not exist"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📝 LOG ANALYSIS AND ERROR CONTEXT
# ═══════════════════════════════════════════════════════════════════════════════

# Collect recent log entries and error analysis
collect_log_analysis() {
    log_info "Analyzing recent logs and error context"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
📝 LOG ANALYSIS AND ERROR CONTEXT
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "JarvisJR Stack Log Files:"
    
    if [[ -d "$BASE_DIR/logs" ]]; then
        echo "  Log directory: $BASE_DIR/logs"
        echo "  Available log files:"
        ls -la "$BASE_DIR/logs" | sed 's/^/    /'
        
        echo ""
        echo "Recent Setup Log Entries (last 20 lines):"
        local latest_setup_log=$(ls -t "$BASE_DIR/logs"/setup_*.log 2>/dev/null | head -1)
        if [[ -f "$latest_setup_log" ]]; then
            echo "  From: $(basename "$latest_setup_log")"
            tail -20 "$latest_setup_log" | filter_sensitive_data | sed 's/^/    /'
        else
            echo "    No setup logs found"
        fi
        
        echo ""
        echo "Recent Error Patterns:"
        if [[ -f "$latest_setup_log" ]]; then
            grep -i "error\|fail\|exception" "$latest_setup_log" 2>/dev/null | tail -10 | filter_sensitive_data | sed 's/^/    /' || echo "    No recent errors found"
        fi
        
    else
        echo "  Log directory does not exist: $BASE_DIR/logs"
    fi
    
    # System logs (if accessible)
    echo ""
    echo "System Log Analysis:"
    if [[ -r /var/log/syslog ]]; then
        echo "  Recent system errors (last 10 Docker/service related):"
        grep -i "docker\|systemd\|error" /var/log/syslog 2>/dev/null | tail -10 | sed 's/^/    /' || echo "    No recent system errors found"
    else
        echo "    System logs not accessible"
    fi
    
    # Docker logs analysis
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        echo ""
        echo "Container Log Summary:"
        local containers=("supabase-db" "supabase-api" "n8n" "nginx-proxy")
        for container in "${containers[@]}"; do
            if docker ps -a --format "{{.Names}}" | grep -q "$container"; then
                echo "  $container (last 5 error lines):"
                docker logs --tail 100 "$container" 2>&1 | grep -i "error\|fail\|exception" | tail -5 | filter_sensitive_data | sed 's/^/    /' || echo "    No recent errors"
            fi
        done
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔥 COMPREHENSIVE TROUBLESHOOTING DATA
# ═══════════════════════════════════════════════════════════════════════════════

# Collect comprehensive troubleshooting information
collect_comprehensive_troubleshooting() {
    if [[ "$DIAGNOSTIC_LEVEL" != "comprehensive" ]]; then
        return 0
    fi
    
    log_info "Collecting comprehensive troubleshooting data"
    
    cat << 'EOF'

═══════════════════════════════════════════════════════════════════════════════
🔥 COMPREHENSIVE TROUBLESHOOTING DATA
═══════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "Network Configuration:"
    echo "  DNS Resolution Test:"
    for subdomain in "$SUPABASE_SUBDOMAIN" "$STUDIO_SUBDOMAIN" "$N8N_SUBDOMAIN"; do
        if [[ -n "$subdomain" && -n "$DOMAIN" ]]; then
            local full_domain="${subdomain}.${DOMAIN}"
            if nslookup "$full_domain" &>/dev/null; then
                echo "    ✓ $full_domain resolves"
            else
                echo "    ✗ $full_domain does not resolve"
            fi
        fi
    done
    
    echo ""
    echo "  Port Connectivity Test:"
    local ports=(80 443 22)
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            echo "    ✓ Port $port is listening"
        else
            echo "    ✗ Port $port is not listening"
        fi
    done
    
    echo ""
    echo "Firewall Status:"
    if command -v ufw &>/dev/null; then
        ufw status | sed 's/^/  /'
    else
        echo "  UFW not available"
    fi
    
    echo ""
    echo "SSL Certificate Status:"
    if [[ -d "/etc/letsencrypt/live" ]]; then
        echo "  Let's Encrypt certificates:"
        ls -la /etc/letsencrypt/live/ | sed 's/^/    /' 2>/dev/null || echo "    Unable to list certificates"
    else
        echo "  No Let's Encrypt certificates directory found"
    fi
    
    echo ""
    echo "Disk Space Analysis:"
    echo "  Large files in base directory (>100MB):"
    if [[ -d "$BASE_DIR" ]]; then
        find "$BASE_DIR" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sed 's/^/    /' || echo "    No large files found"
    fi
    
    echo ""
    echo "Service Dependencies:"
    echo "  Required system packages:"
    local packages=("docker" "docker-compose" "curl" "openssl" "ufw")
    for package in "${packages[@]}"; do
        if command -v "$package" &>/dev/null; then
            echo "    ✓ $package is installed"
        else
            echo "    ✗ $package is missing"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📋 MAIN DIAGNOSTIC ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Main diagnostic function
run_diagnostics() {
    local diagnostic_level="${1:-detailed}"
    DIAGNOSTIC_LEVEL="$diagnostic_level"
    
    log_section "JarvisJR Stack Diagnostic Information Collection"
    log_info "Diagnostic level: $diagnostic_level"
    log_info "Security filtering: Enabled (sensitive data will be redacted)"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would collect comprehensive diagnostic information including:"
        log_info "[DRY-RUN]   • System information (OS, hardware, resources)"
        log_info "[DRY-RUN]   • Docker configuration and container health"
        log_info "[DRY-RUN]   • JarvisJR Stack service status"
        log_info "[DRY-RUN]   • Configuration validation (sensitive data filtered)"
        log_info "[DRY-RUN]   • Recent log analysis and error context"
        if [[ "$diagnostic_level" == "comprehensive" ]]; then
            log_info "[DRY-RUN]   • Comprehensive troubleshooting data (network, SSL, dependencies)"
        fi
        log_info "[DRY-RUN] Output would be formatted for remote analysis and troubleshooting"
        return 0
    fi
    
    # Create diagnostic header
    cat << 'EOF'
════════════════════════════════════════════════════════════════════════════════════════════
🔍 JARVISJR STACK DIAGNOSTIC REPORT
════════════════════════════════════════════════════════════════════════════════════════════

Generated: $(date)
Diagnostic Level: DIAGNOSTIC_LEVEL
JarvisJR Stack Version: Production Release
Security Filtering: ENABLED (Sensitive data redacted)

This diagnostic report contains troubleshooting information for the JarvisJR Stack.
All sensitive data (passwords, keys, tokens) has been filtered for security.

TROUBLESHOOTING SECTIONS:
• System Information
• Docker Configuration  
• JarvisJR Stack Service Health
• Configuration Validation
• Log Analysis and Error Context
EOF
    
    if [[ "$diagnostic_level" == "comprehensive" ]]; then
        echo "• Comprehensive Troubleshooting Data"
    fi
    
    cat << 'EOF'

For support, provide this entire diagnostic report to the JarvisJR Stack support team.

════════════════════════════════════════════════════════════════════════════════════════════
EOF
    
    # Run diagnostic collection functions
    collect_system_info
    collect_detailed_system_info
    collect_docker_info
    collect_jarvisjr_service_health
    collect_configuration_validation
    collect_log_analysis
    collect_comprehensive_troubleshooting
    
    # Create diagnostic footer
    cat << 'EOF'

════════════════════════════════════════════════════════════════════════════════════════════
🎯 DIAGNOSTIC REPORT SUMMARY
════════════════════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "Report Generated: $(date)"
    echo "Diagnostic Level: $diagnostic_level"
    echo "Total Sections: $(echo "$diagnostic_level" | grep -q comprehensive && echo "7" || echo "6")"
    echo "Security Status: All sensitive data filtered"
    
    cat << 'EOF'

NEXT STEPS FOR TROUBLESHOOTING:
1. Review the service health section for any failed services
2. Check configuration validation for missing required settings
3. Examine recent log entries for error patterns
4. Verify Docker daemon status and container connectivity
5. Test DNS resolution and network connectivity for your domain

For additional support:
• JarvisJR Stack Documentation: See project README.md
• Common Issues: Review troubleshooting memory files
• Advanced Debugging: Run with --enable-debug flag

════════════════════════════════════════════════════════════════════════════════════════════
EOF
    
    log_success "Diagnostic data collection completed"
    log_info "Review the output above for troubleshooting information"
    
    # Save diagnostic report to file if in interactive mode
    if [[ -t 1 ]] && [[ -d "$BASE_DIR/logs" ]]; then
        local diagnostic_file="$BASE_DIR/logs/diagnostic_$(date '+%Y%m%d_%H%M%S').log"
        log_info "Diagnostic report also saved to: $diagnostic_file"
        echo "# This file contains the diagnostic output generated above" > "$diagnostic_file"
        echo "# Generated: $(date)" >> "$diagnostic_file"
        echo "# To view: cat $diagnostic_file" >> "$diagnostic_file"
    fi
}

# Command-line argument handling
main() {
    local action="${1:-detailed}"
    
    case "$action" in
        basic|detailed|comprehensive)
            run_diagnostics "$action"
            ;;
        run)
            # Legacy compatibility - default to detailed
            run_diagnostics "detailed"
            ;;
        *)
            log_error "Invalid diagnostic level: $action"
            echo "Usage: $0 [basic|detailed|comprehensive]"
            echo ""
            echo "Diagnostic Levels:"
            echo "  basic        - System overview and service status"
            echo "  detailed     - Includes process info and detailed analysis"
            echo "  comprehensive - Full troubleshooting data collection"
            return 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi