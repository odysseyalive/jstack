#!/bin/bash
# Container Runtime Security Monitoring for JStack Stack
# Implements real-time security monitoring, anomaly detection, and automated response

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 RUNTIME SECURITY MONITORING SETUP
# ═══════════════════════════════════════════════════════════════════════════════

setup_falco_monitoring() {
    log_section "Setting up Falco Runtime Security Monitoring"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Falco runtime security monitoring"
        return 0
    fi
    
    start_section_timer "Falco Setup"
    
    # Detect OS and install Falco
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            "arch")
                execute_cmd "sudo pacman -S --noconfirm falco" "Install Falco (Arch)"
                ;;
            "ubuntu"|"debian")
                execute_cmd "curl -s https://falco.org/repo/falcosecurity-packages.asc | sudo apt-key add -" "Add Falco GPG key"
                execute_cmd "echo 'deb https://download.falco.org/packages/deb stable main' | sudo tee -a /etc/apt/sources.list.d/falcosecurity.list" "Add Falco repository"
                execute_cmd "sudo apt-get update && sudo apt-get install -y falco" "Install Falco (Debian/Ubuntu)"
                ;;
            *)
                log_info "Installing Falco via container method"
                setup_falco_container
                return 0
                ;;
        esac
    fi
    
    # Configure Falco for JStack Stack
    create_falco_configuration
    
    end_section_timer "Falco Setup"
}

setup_falco_container() {
    log_info "Setting up Falco as container-based monitoring"
    
    local monitoring_dir="$BASE_DIR/security/monitoring"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $monitoring_dir" "Create monitoring directory"
    
    # Falco Docker Compose configuration
    cat > /tmp/falco-monitoring.yml << EOF
version: '3.8'

services:
  falco:
    image: falcosecurity/falco:latest
    container_name: falco-security
    restart: unless-stopped
    
    # Security Configuration
    privileged: true  # Required for kernel module access
    
    # Resource Limits
    mem_limit: 512m
    cpus: 0.5
    
    # Environment
    environment:
      - FALCO_GRPC_ENABLED=true
      - FALCO_GRPC_BIND_ADDRESS=0.0.0.0:5060
      - FALCO_K8S_AUDIT_ENDPOINT=
      - FALCO_LOG_LEVEL=INFO
      
    # Volumes for system monitoring
    volumes:
      - /var/run/docker.sock:/host/var/run/docker.sock:ro
      - /dev:/host/dev:ro
      - /proc:/host/proc:ro
      - /boot:/host/boot:ro
      - /lib/modules:/host/lib/modules:ro
      - /usr:/host/usr:ro
      - /etc:/host/etc:ro
      - $monitoring_dir/falco:/etc/falco:ro
      - $monitoring_dir/logs:/var/log/falco:rw
    
    # Network
    networks:
      - monitoring_net
    
    # Command
    command: ["falco", "--modern-bpf"]
    
    # Health Check
    healthcheck:
      test: ["CMD-SHELL", "pgrep falco || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
    
    # Logging
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  monitoring_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.25.0.0/16
EOF
    
    safe_mv "/tmp/falco-monitoring.yml" "$monitoring_dir/falco-monitoring.yml" "Install Falco container config"
}

create_falco_configuration() {
    log_section "Creating Falco Security Rules Configuration"
    
    local monitoring_dir="$BASE_DIR/security/monitoring"
    local falco_config_dir="$monitoring_dir/falco"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $falco_config_dir" "Create Falco config directory"
    
    # Custom Falco rules for JStack Stack
    cat > /tmp/jarvis_security_rules.yaml << 'EOF'
# JStack Stack Custom Security Rules for Falco

# Container Security Rules
- rule: JStack Container Running as Root
  desc: Detect JStack containers running as root user
  condition: >
    spawned_process and
    container and
    container.name matches (n8n|supabase|nginx) and
    proc.uid = 0
  output: >
    JStack container running as root detected 
    (container=%container.name uid=%proc.uid command=%proc.cmdline)
  priority: CRITICAL
  tags: [container, security, jarvis]

- rule: JStack Suspicious Network Activity
  desc: Detect suspicious network connections from JStack containers
  condition: >
    outbound and
    container and
    container.name matches (n8n|supabase) and
    not fd.sip matches (127.0.0.1|172.20.0.0/16|172.21.0.0/16|172.22.0.0/16) and
    not fd.sport in (80, 443, 53, 5432, 5678, 8000, 3000)
  output: >
    Suspicious outbound connection from JStack container 
    (container=%container.name dest=%fd.sip:%fd.sport command=%proc.cmdline)
  priority: WARNING
  tags: [network, security, jarvis]

- rule: JStack File System Tampering
  desc: Detect unauthorized file modifications in JStack containers
  condition: >
    open_write and
    container and
    container.name matches (n8n|supabase|nginx) and
    (fd.name startswith /etc/ or
     fd.name startswith /usr/bin/ or
     fd.name startswith /bin/)
  output: >
    File system tampering detected in JStack container 
    (container=%container.name file=%fd.name command=%proc.cmdline)
  priority: HIGH
  tags: [filesystem, security, jarvis]

- rule: JStack Privilege Escalation Attempt
  desc: Detect privilege escalation attempts in JStack containers
  condition: >
    spawned_process and
    container and
    container.name matches (n8n|supabase|nginx) and
    (proc.name in (sudo, su, passwd, chsh, newgrp, setuid, setgid) or
     proc.cmdline contains chmod and proc.cmdline contains +s)
  output: >
    Privilege escalation attempt detected in JStack container 
    (container=%container.name command=%proc.cmdline uid=%proc.uid)
  priority: CRITICAL
  tags: [privilege, security, jarvis]

# Database Security Rules
- rule: JStack Database Suspicious Query
  desc: Detect suspicious database queries from N8N
  condition: >
    spawned_process and
    container.name = "supabase-db" and
    (proc.cmdline contains "DROP TABLE" or
     proc.cmdline contains "DELETE FROM" and proc.cmdline contains "*" or
     proc.cmdline contains "UPDATE" and proc.cmdline contains "SET" and proc.cmdline contains "*")
  output: >
    Suspicious database query detected 
    (container=%container.name query=%proc.cmdline)
  priority: HIGH
  tags: [database, security, jarvis]

# Browser Automation Security Rules
- rule: JStack Chrome Sandbox Escape
  desc: Detect Chrome sandbox escape attempts
  condition: >
    spawned_process and
    container.name = "n8n" and
    proc.name = "chrome" and
    (proc.cmdline contains "--no-sandbox" or
     proc.cmdline contains "--disable-setuid-sandbox")
  output: >
    Chrome sandbox escape attempt detected 
    (container=%container.name command=%proc.cmdline)
  priority: CRITICAL
  tags: [browser, security, jarvis]

# System Security Rules
- rule: JStack Container Escape Attempt
  desc: Detect container escape attempts
  condition: >
    spawned_process and
    container and
    container.name matches (n8n|supabase|nginx) and
    (proc.cmdline contains "docker" or
     proc.cmdline contains "runc" or
     proc.cmdline contains "kubectl" or
     proc.name in (nsenter, unshare))
  output: >
    Container escape attempt detected 
    (container=%container.name command=%proc.cmdline)
  priority: CRITICAL
  tags: [container, escape, security, jarvis]
EOF
    
    safe_mv "/tmp/jarvis_security_rules.yaml" "$falco_config_dir/jarvis_security_rules.yaml" "Install custom security rules"
    
    # Main Falco configuration
    cat > /tmp/falco.yaml << 'EOF'
# Falco Configuration for JStack Stack

# Rules files to load
rules_file:
  - /etc/falco/falco_rules.yaml
  - /etc/falco/falco_rules.local.yaml
  - /etc/falco/rules.d
  - /etc/falco/jarvis_security_rules.yaml

# Time format for output
time_format_iso_8601: false

# JSON output
json_output: true
json_include_output_property: true
json_include_tags_property: true

# Log outputs
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/falco_events.log

stdout_output:
  enabled: true

# gRPC server
grpc:
  enabled: true
  bind_address: "0.0.0.0:5060"
  threadiness: 0

# HTTP output (for webhooks)
http_output:
  enabled: false
  url: ""

# Buffered outputs
buffered_outputs: false

# Output format
output_timeout: 2000
outputs_queue_capacity: 1000

# System call event drops
syscall_event_drops:
  actions:
    - log
    - alert
  rate: 0.03333
  max_burst: 1000

# Modern BPF probe
modern_bpf:
  enabled: true

# Log level
log_level: info
log_stderr: true
log_syslog: true

# Performance
metadata_download:
  max_mb: 100
  chunk_wait_us: 1000
  watch_freq_sec: 1

priority: debug

# Load plugins
plugins:
  - name: k8saudit
    library_path: libk8saudit.so
    init_config: ""
  - name: cloudtrail
    library_path: libcloudtrail.so
EOF
    
    safe_mv "/tmp/falco.yaml" "$falco_config_dir/falco.yaml" "Install Falco main config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$falco_config_dir/" "Set Falco config ownership"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 SECURITY METRICS AND MONITORING
# ═══════════════════════════════════════════════════════════════════════════════

setup_security_metrics() {
    log_section "Setting up Security Metrics Collection"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup security metrics collection"
        return 0
    fi
    
    start_section_timer "Security Metrics"
    
    local monitoring_dir="$BASE_DIR/security/monitoring"
    
    # Security monitoring script
    cat > /tmp/security-monitor.sh << 'EOF'
#!/bin/bash
# Security Monitoring Script for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

MONITORING_LOG="/home/jarvis/jstack/logs/security-monitor.log"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEM=85

log_security_event() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$MONITORING_LOG"
}

monitor_container_resources() {
    local containers=("n8n" "supabase-db" "nginx-proxy")
    
    for container in "${containers[@]}"; do
        if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
            local stats=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "$container" 2>/dev/null)
            
            if [[ -n "$stats" ]]; then
                local cpu_usage=$(echo "$stats" | tail -n1 | awk '{print $2}' | sed 's/%//')
                local mem_usage=$(echo "$stats" | tail -n1 | awk '{print $4}' | sed 's/%//')
                
                # Check CPU threshold
                if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l 2>/dev/null || echo "0") )); then
                    log_security_event "WARNING" "High CPU usage detected: $container ($cpu_usage%)"
                fi
                
                # Check Memory threshold
                if (( $(echo "$mem_usage > $ALERT_THRESHOLD_MEM" | bc -l 2>/dev/null || echo "0") )); then
                    log_security_event "WARNING" "High memory usage detected: $container ($mem_usage%)"
                fi
            fi
        fi
    done
}

monitor_failed_login_attempts() {
    # Monitor auth logs for failed attempts
    if [[ -f /var/log/auth.log ]]; then
        local failed_attempts=$(grep "Failed password" /var/log/auth.log | grep "$(date '+%b %d')" | wc -l)
        if [[ $failed_attempts -gt 10 ]]; then
            log_security_event "CRITICAL" "High number of failed login attempts detected: $failed_attempts"
        fi
    fi
}

monitor_docker_events() {
    # Monitor Docker events for security-relevant activities
    docker events --filter type=container --format "{{.Time}} {{.Action}} {{.Actor.Attributes.name}}" --since="$(date -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S')" 2>/dev/null | while read -r event; do
        if [[ "$event" =~ (start|stop|kill|die) ]]; then
            log_security_event "INFO" "Container event: $event"
        fi
    done
}

check_file_integrity() {
    # Check integrity of critical configuration files
    local config_files=(
        "/home/jarvis/jstack/jstack.config"
        "/home/jarvis/jstack/services/nginx/conf/nginx.conf"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            local current_hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
            local stored_hash_file="${file}.sha256"
            
            if [[ -f "$stored_hash_file" ]]; then
                local stored_hash=$(cat "$stored_hash_file")
                if [[ "$current_hash" != "$stored_hash" ]]; then
                    log_security_event "WARNING" "File integrity check failed: $file"
                fi
            else
                # Create initial hash
                echo "$current_hash" > "$stored_hash_file"
                log_security_event "INFO" "Created integrity hash for: $file"
            fi
        fi
    done
}

generate_security_report() {
    log_info "Generating security monitoring report..."
    
    local report_file="/home/jarvis/jstack/logs/security-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "JStack Stack Security Report"
        echo "Generated: $(date)"
        echo "=============================="
        echo ""
        
        echo "Container Status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(n8n|supabase|nginx)"
        echo ""
        
        echo "Recent Security Events (Last 24h):"
        if [[ -f "$MONITORING_LOG" ]]; then
            tail -50 "$MONITORING_LOG" | grep "$(date -d '1 day ago' '+%Y-%m-%d')" || echo "No events found"
        else
            echo "No monitoring log found"
        fi
        echo ""
        
        echo "Resource Usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | grep -E "(n8n|supabase|nginx)" || echo "Unable to get stats"
        echo ""
        
        echo "Network Connections:"
        ss -tuln | grep -E ":80|:443|:5432|:5678|:8000|:3000" || echo "No relevant connections found"
        
    } > "$report_file"
    
    log_success "Security report generated: $report_file"
}

case "${1:-monitor}" in
    "resources") monitor_container_resources ;;
    "auth") monitor_failed_login_attempts ;;
    "docker") monitor_docker_events ;;
    "integrity") check_file_integrity ;;
    "report") generate_security_report ;;
    "monitor"|"all")
        monitor_container_resources
        monitor_failed_login_attempts
        monitor_docker_events
        check_file_integrity
        ;;
    *) echo "Usage: $0 [monitor|resources|auth|docker|integrity|report|all]"
       echo "Security monitoring for JStack Stack" ;;
esac
EOF
    
    safe_mv "/tmp/security-monitor.sh" "$monitoring_dir/security-monitor.sh" "Install security monitoring script"
    execute_cmd "chmod +x $monitoring_dir/security-monitor.sh" "Make monitoring script executable"
    
    # Create systemd service for continuous monitoring
    if command -v systemctl >/dev/null 2>&1; then
        create_monitoring_service "$monitoring_dir"
    fi
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$monitoring_dir/" "Set monitoring directory ownership"
    
    end_section_timer "Security Metrics"
}

create_monitoring_service() {
    local monitoring_dir="$1"
    
    log_info "Creating systemd service for security monitoring"
    
    cat > /tmp/jstack-security-monitor.service << EOF
[Unit]
Description=JStack Stack Security Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$monitoring_dir/security-monitor.sh monitor
Restart=always
RestartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    execute_cmd "sudo mv /tmp/jstack-security-monitor.service /etc/systemd/system/" "Install monitoring service"
    execute_cmd "sudo systemctl daemon-reload" "Reload systemd"
    execute_cmd "sudo systemctl enable jstack-security-monitor" "Enable monitoring service"
    
    # Create timer for periodic reports
    cat > /tmp/jstack-security-report.service << EOF
[Unit]
Description=JStack Stack Security Report Generator
After=docker.service

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$monitoring_dir/security-monitor.sh report
EOF
    
    cat > /tmp/jstack-security-report.timer << 'EOF'
[Unit]
Description=Run JStack security report daily
Requires=jstack-security-report.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    execute_cmd "sudo mv /tmp/jstack-security-report.service /etc/systemd/system/" "Install report service"
    execute_cmd "sudo mv /tmp/jstack-security-report.timer /etc/systemd/system/" "Install report timer"
    execute_cmd "sudo systemctl daemon-reload" "Reload systemd for timer"
    execute_cmd "sudo systemctl enable jstack-security-report.timer" "Enable report timer"
}

# Main function
main() {
    case "${1:-setup}" in
        "falco") setup_falco_monitoring ;;
        "metrics") setup_security_metrics ;;
        "setup"|"all") 
            setup_falco_monitoring
            setup_security_metrics
            ;;
        "start") 
            sudo systemctl start jstack-security-monitor 2>/dev/null || log_warning "Could not start monitoring service"
            sudo systemctl start jstack-security-report.timer 2>/dev/null || log_warning "Could not start report timer"
            ;;
        "stop")
            sudo systemctl stop jstack-security-monitor 2>/dev/null || log_warning "Could not stop monitoring service"
            sudo systemctl stop jstack-security-report.timer 2>/dev/null || log_warning "Could not stop report timer"
            ;;
        "status")
            systemctl status jstack-security-monitor 2>/dev/null || echo "Monitoring service not found"
            systemctl status jstack-security-report.timer 2>/dev/null || echo "Report timer not found"
            ;;
        *) echo "Usage: $0 [setup|falco|metrics|start|stop|status|all]"
           echo "Runtime security monitoring for JStack Stack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi