#!/bin/bash
# Automated Threat Response System for JStack Stack
# Implements intelligent threat detection, automated response, and incident management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🚨 AUTOMATED THREAT RESPONSE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

setup_threat_response() {
    log_section "Setting up Automated Threat Response System"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup automated threat response system"
        return 0
    fi
    
    start_section_timer "Threat Response Setup"
    
    local threat_dir="$BASE_DIR/security/threat-response"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $threat_dir" "Create threat response directory"
    
    # Create threat detection engine
    create_threat_detection_engine "$threat_dir"
    
    # Create automated response system
    create_automated_response_system "$threat_dir"
    
    # Create incident management system
    create_incident_management_system "$threat_dir"
    
    # Set up systemd services
    setup_threat_response_services "$threat_dir"
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$threat_dir/" "Set threat response ownership"
    
    end_section_timer "Threat Response Setup"
    log_success "Automated threat response system configured"
}

create_threat_detection_engine() {
    local threat_dir="$1"
    
    log_info "Creating threat detection engine"
    
    cat > /tmp/threat-detector.sh << 'EOF'
#!/bin/bash
# Threat Detection Engine for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Configuration
THREAT_LOG="${BASE_DIR}/logs/security/threats.log"
INCIDENT_LOG="${BASE_DIR}/logs/security/incidents.log"
CONFIG_FILE="${BASE_DIR}/security/threat-response/threat-config.json"

# Ensure log directories exist
mkdir -p "$(dirname "$THREAT_LOG")"
mkdir -p "$(dirname "$INCIDENT_LOG")"

# Threat detection thresholds
FAILED_LOGIN_THRESHOLD=5
RATE_LIMIT_THRESHOLD=20
WAF_BLOCK_THRESHOLD=10
SCANNING_THRESHOLD=15

log_threat() {
    local level="$1"
    local ip="$2" 
    local threat_type="$3"
    local details="$4"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] IP=$ip TYPE=$threat_type DETAILS=$details" >> "$THREAT_LOG"
}

detect_brute_force_attacks() {
    log_info "Detecting brute force attacks"
    
    local nginx_log="${BASE_DIR}/logs/nginx/access.log"
    local time_window="$(date -d '5 minutes ago' '+%d/%b/%Y:%H:%M')"
    
    if [[ -f "$nginx_log" ]]; then
        # Detect failed login attempts
        grep "$time_window" "$nginx_log" | grep "401\|403" | \
            awk '{print $1}' | sort | uniq -c | sort -nr | \
            while read count ip; do
                if [[ $count -ge $FAILED_LOGIN_THRESHOLD ]]; then
                    log_threat "HIGH" "$ip" "BRUTE_FORCE" "Failed logins: $count in 5min"
                    echo "$ip:BRUTE_FORCE:$count" >> /tmp/active-threats.txt
                fi
            done
    fi
}

detect_rate_limit_violations() {
    log_info "Detecting rate limit violations"
    
    local nginx_error_log="${BASE_DIR}/logs/nginx/error.log"
    local time_window="$(date -d '5 minutes ago' '+%Y/%m/%d %H:%M')"
    
    if [[ -f "$nginx_error_log" ]]; then
        # Detect rate limiting violations
        grep "$time_window" "$nginx_error_log" | grep "limiting requests" | \
            grep -o "client: [0-9.]*" | awk '{print $2}' | sort | uniq -c | sort -nr | \
            while read count ip; do
                if [[ $count -ge $RATE_LIMIT_THRESHOLD ]]; then
                    log_threat "MEDIUM" "$ip" "RATE_LIMIT" "Violations: $count in 5min"
                    echo "$ip:RATE_LIMIT:$count" >> /tmp/active-threats.txt
                fi
            done
    fi
}

detect_waf_triggers() {
    log_info "Detecting WAF trigger patterns"
    
    local waf_log="${BASE_DIR}/logs/nginx/waf-blocks.log"
    local time_window="$(date -d '10 minutes ago' '+%d/%b/%Y:%H:%M')"
    
    if [[ -f "$waf_log" ]]; then
        # Detect repeated WAF blocks
        grep "$time_window" "$waf_log" | \
            awk '{print $1}' | sort | uniq -c | sort -nr | \
            while read count ip; do
                if [[ $count -ge $WAF_BLOCK_THRESHOLD ]]; then
                    log_threat "HIGH" "$ip" "WAF_TRIGGER" "Blocks: $count in 10min"
                    echo "$ip:WAF_TRIGGER:$count" >> /tmp/active-threats.txt
                fi
            done
    fi
}

detect_scanning_activity() {
    log_info "Detecting scanning and reconnaissance"
    
    local nginx_log="${BASE_DIR}/logs/nginx/access.log"
    local time_window="$(date -d '10 minutes ago' '+%d/%b/%Y:%H:%M')"
    
    if [[ -f "$nginx_log" ]]; then
        # Detect scanning patterns (many 404s, suspicious paths)
        grep "$time_window" "$nginx_log" | grep "404" | \
            grep -E "(\.php|\.asp|wp-admin|admin|phpmyadmin|\.env)" | \
            awk '{print $1}' | sort | uniq -c | sort -nr | \
            while read count ip; do
                if [[ $count -ge $SCANNING_THRESHOLD ]]; then
                    log_threat "MEDIUM" "$ip" "SCANNING" "404 requests: $count in 10min"
                    echo "$ip:SCANNING:$count" >> /tmp/active-threats.txt
                fi
            done
    fi
}

detect_anomalous_traffic() {
    log_info "Detecting anomalous traffic patterns"
    
    local nginx_log="${BASE_DIR}/logs/nginx/access.log"
    local current_hour=$(date '+%H')
    local current_minute=$(date '+%M')
    
    if [[ -f "$nginx_log" ]]; then
        # Detect unusual request volumes
        local current_requests=$(grep "$(date '+%d/%b/%Y:%H:%M')" "$nginx_log" | wc -l)
        local avg_requests=50  # Baseline - should be calculated from historical data
        
        if [[ $current_requests -gt $((avg_requests * 3)) ]]; then
            log_threat "MEDIUM" "MULTIPLE" "TRAFFIC_SPIKE" "Requests: $current_requests (avg: $avg_requests)"
            echo "TRAFFIC_SPIKE:ANOMALY:$current_requests" >> /tmp/active-threats.txt
        fi
        
        # Detect unusual user agents
        grep "$(date '+%d/%b/%Y:%H')" "$nginx_log" | \
            grep -oP '"[^"]*" [0-9]+ [0-9]+ "[^"]*" "\K[^"]*' | \
            grep -E "(bot|crawler|scanner|curl|wget|python|perl)" | \
            sort | uniq -c | sort -nr | head -5 | \
            while read count agent; do
                if [[ $count -gt 20 ]]; then
                    local sample_ip=$(grep "$agent" "$nginx_log" | tail -1 | awk '{print $1}')
                    log_threat "LOW" "$sample_ip" "SUSPICIOUS_AGENT" "Agent: $agent Count: $count"
                fi
            done
    fi
}

analyze_threat_patterns() {
    log_info "Analyzing threat patterns and correlations"
    
    if [[ -f /tmp/active-threats.txt ]]; then
        # Correlate multiple threat types from same IP
        awk -F: '{print $1}' /tmp/active-threats.txt | sort | uniq -c | sort -nr | \
            while read count ip; do
                if [[ $count -ge 3 ]]; then
                    local threats=$(grep "^$ip:" /tmp/active-threats.txt | cut -d: -f2 | tr '\n' ',' | sed 's/,$//')
                    log_threat "CRITICAL" "$ip" "MULTI_THREAT" "Types: $threats Count: $count"
                    
                    # Escalate to incident management
                    echo "$(date '+%Y-%m-%d %H:%M:%S') CRITICAL INCIDENT: IP $ip showing multiple threat patterns: $threats" >> "$INCIDENT_LOG"
                    
                    # Trigger automated response
                    bash "$(dirname "$0")/automated-response.sh" block-ip "$ip" "multi-threat" &
                fi
            done
    fi
}

generate_threat_report() {
    log_info "Generating threat detection report"
    
    local report_file="${BASE_DIR}/logs/security/threat-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "JStack Stack Threat Detection Report"
        echo "Generated: $(date)"
        echo "======================================="
        echo ""
        
        echo "=== Active Threats (Last Hour) ==="
        if [[ -f "$THREAT_LOG" ]]; then
            grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')" "$THREAT_LOG" | tail -20 || echo "No threats detected"
        else
            echo "No threat log found"
        fi
        echo ""
        
        echo "=== Threat Summary ==="
        local threat_types=("BRUTE_FORCE" "RATE_LIMIT" "WAF_TRIGGER" "SCANNING" "TRAFFIC_SPIKE")
        for threat_type in "${threat_types[@]}"; do
            local count=$(grep "$threat_type" "$THREAT_LOG" 2>/dev/null | wc -l || echo "0")
            echo "$threat_type: $count incidents"
        done
        echo ""
        
        echo "=== Top Threat Sources ==="
        if [[ -f "$THREAT_LOG" ]]; then
            grep "$(date '+%Y-%m-%d')" "$THREAT_LOG" | grep -o "IP=[0-9.]*" | \
                cut -d= -f2 | sort | uniq -c | sort -nr | head -10 || echo "No threat sources found"
        fi
        
    } > "$report_file"
    
    log_success "Threat report generated: $report_file"
}

# Clean up temporary files
cleanup() {
    rm -f /tmp/active-threats.txt
}

# Main detection workflow
main() {
    case "${1:-detect}" in
        "brute-force") detect_brute_force_attacks ;;
        "rate-limit") detect_rate_limit_violations ;;
        "waf") detect_waf_triggers ;;
        "scanning") detect_scanning_activity ;;
        "anomalous") detect_anomalous_traffic ;;
        "analyze") analyze_threat_patterns ;;
        "report") generate_threat_report ;;
        "detect"|"all")
            # Clear previous run data
            > /tmp/active-threats.txt
            
            # Run all detection methods
            detect_brute_force_attacks
            detect_rate_limit_violations
            detect_waf_triggers
            detect_scanning_activity
            detect_anomalous_traffic
            
            # Analyze patterns and correlations
            analyze_threat_patterns
            
            # Cleanup
            cleanup
            ;;
        *) echo "Usage: $0 [detect|brute-force|rate-limit|waf|scanning|anomalous|analyze|report|all]" ;;
    esac
}

main "$@"
EOF
    
    safe_mv "/tmp/threat-detector.sh" "$threat_dir/threat-detector.sh" "Install threat detector"
    execute_cmd "chmod +x $threat_dir/threat-detector.sh" "Make threat detector executable"
}

create_automated_response_system() {
    local threat_dir="$1"
    
    log_info "Creating automated response system"
    
    cat > /tmp/automated-response.sh << 'EOF'
#!/bin/bash
# Automated Response System for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

RESPONSE_LOG="${BASE_DIR}/logs/security/responses.log"
BLOCKED_IPS_FILE="${BASE_DIR}/security/nginx/dynamic-blocks.conf"

# Ensure directories exist
mkdir -p "$(dirname "$RESPONSE_LOG")"
mkdir -p "$(dirname "$BLOCKED_IPS_FILE")"

log_response() {
    local action="$1"
    local target="$2"
    local reason="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] ACTION=$action TARGET=$target REASON=$reason" >> "$RESPONSE_LOG"
}

# Block IP address
block_ip() {
    local ip="$1"
    local reason="${2:-security-threat}"
    local duration="${3:-3600}"  # Default 1 hour
    
    log_info "Blocking IP: $ip (Reason: $reason)"
    
    # Validate IP format
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP format: $ip"
        return 1
    fi
    
    # Add to NGINX blocklist
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local expiry=$(date -d "+${duration} seconds" '+%Y-%m-%d %H:%M:%S')
    echo "deny $ip; # Blocked: $timestamp | Reason: $reason | Expires: $expiry" >> "$BLOCKED_IPS_FILE"
    
    # Add to iptables for immediate blocking
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -s "$ip" -j DROP 2>/dev/null || true
        log_info "Added iptables rule for $ip"
    fi
    
    # Add to fail2ban if available
    if command -v fail2ban-client >/dev/null 2>&1; then
        fail2ban-client set nginx-badbots banip "$ip" 2>/dev/null || true
        log_info "Added to fail2ban banlist: $ip"
    fi
    
    # Reload NGINX configuration
    if command -v nginx >/dev/null 2>&1; then
        nginx -t 2>/dev/null && nginx -s reload 2>/dev/null
        log_success "NGINX configuration reloaded"
    fi
    
    log_response "BLOCK_IP" "$ip" "$reason"
    
    # Send notification if configured
    send_security_notification "IP Blocked" "Blocked $ip for $reason (duration: ${duration}s)"
}

# Unblock IP address
unblock_ip() {
    local ip="$1"
    local reason="${2:-manual-unblock}"
    
    log_info "Unblocking IP: $ip"
    
    # Remove from NGINX blocklist
    if [[ -f "$BLOCKED_IPS_FILE" ]]; then
        sed -i "/deny $ip;/d" "$BLOCKED_IPS_FILE"
    fi
    
    # Remove from iptables
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null || true
        log_info "Removed iptables rule for $ip"
    fi
    
    # Remove from fail2ban
    if command -v fail2ban-client >/dev/null 2>&1; then
        fail2ban-client set nginx-badbots unbanip "$ip" 2>/dev/null || true
        log_info "Removed from fail2ban banlist: $ip"
    fi
    
    # Reload NGINX
    if command -v nginx >/dev/null 2>&1; then
        nginx -t 2>/dev/null && nginx -s reload 2>/dev/null
    fi
    
    log_response "UNBLOCK_IP" "$ip" "$reason"
}

# Rate limiting escalation
escalate_rate_limiting() {
    local ip="$1"
    local current_limit="$2"
    
    log_info "Escalating rate limiting for IP: $ip"
    
    # Create temporary stricter rate limit for this IP
    local temp_config="/tmp/temp-rate-limit-$ip.conf"
    cat > "$temp_config" << RATE_EOF
# Temporary strict rate limiting for $ip
geo \$remote_addr \$rate_limit_$ip {
    default 0;
    $ip 1;
}

map \$rate_limit_$ip \$rate_zone_$ip {
    0 "normal";
    1 "restricted";
}

limit_req_zone \$binary_remote_addr zone=restricted_$ip:1m rate=1r/s;
RATE_EOF
    
    # This would need to be integrated into the main NGINX config
    log_response "ESCALATE_RATE_LIMIT" "$ip" "rate-limit-violation"
}

# Send security notifications
send_security_notification() {
    local subject="$1"
    local message="$2"
    
    # Email notification (if configured)
    if [[ -n "${ALERT_EMAIL:-}" ]] && command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "JStack Security Alert: $subject" "$ALERT_EMAIL" 2>/dev/null || true
    fi
    
    # Slack notification (if webhook configured)
    if [[ -n "${SLACK_WEBHOOK:-}" ]] && command -v curl >/dev/null 2>&1; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 JStack Security Alert: $subject\n$message\"}" \
            "$SLACK_WEBHOOK" 2>/dev/null || true
    fi
    
    # System logger
    logger -t jstack-security "$subject: $message"
}

# Incident escalation
escalate_incident() {
    local ip="$1"
    local threat_types="$2"
    local severity="$3"
    
    log_info "Escalating incident for IP $ip (Severity: $severity)"
    
    case "$severity" in
        "CRITICAL")
            # Immediate block + extended duration
            block_ip "$ip" "critical-threat-multiple-types" 86400  # 24 hours
            send_security_notification "CRITICAL Security Incident" \
                "IP $ip showing multiple threat patterns: $threat_types. Blocked for 24 hours."
            ;;
        "HIGH")
            # Block with standard duration
            block_ip "$ip" "high-threat" 3600  # 1 hour
            send_security_notification "HIGH Security Threat" \
                "IP $ip blocked for high-severity threat: $threat_types"
            ;;
        "MEDIUM")
            # Rate limit escalation
            escalate_rate_limiting "$ip" "medium"
            send_security_notification "MEDIUM Security Alert" \
                "Rate limiting escalated for IP $ip: $threat_types"
            ;;
    esac
    
    log_response "ESCALATE_INCIDENT" "$ip" "$severity:$threat_types"
}

# Clean expired blocks
clean_expired_blocks() {
    log_info "Cleaning expired IP blocks"
    
    if [[ ! -f "$BLOCKED_IPS_FILE" ]]; then
        return 0
    fi
    
    local current_time=$(date '+%s')
    local temp_file="/tmp/cleaned-blocks.conf"
    
    while IFS= read -r line; do
        if [[ "$line" =~ Expires:\ (.+)$ ]]; then
            local expire_date="${BASH_REMATCH[1]}"
            local expire_timestamp=$(date -d "$expire_date" '+%s' 2>/dev/null || echo "0")
            
            if [[ $expire_timestamp -gt $current_time ]]; then
                echo "$line" >> "$temp_file"
            else
                # Extract IP from expired block
                local expired_ip=$(echo "$line" | grep -o "deny [0-9.]*" | awk '{print $2}')
                if [[ -n "$expired_ip" ]]; then
                    log_info "Expired block removed: $expired_ip"
                    # Remove from iptables too
                    iptables -D INPUT -s "$expired_ip" -j DROP 2>/dev/null || true
                fi
            fi
        else
            # Keep non-expiring entries
            echo "$line" >> "$temp_file"
        fi
    done < "$BLOCKED_IPS_FILE"
    
    mv "$temp_file" "$BLOCKED_IPS_FILE" 2>/dev/null || true
    
    # Reload NGINX
    if command -v nginx >/dev/null 2>&1; then
        nginx -t 2>/dev/null && nginx -s reload 2>/dev/null
    fi
    
    log_response "CLEANUP" "system" "expired-blocks-removed"
}

# Show current response status
show_status() {
    echo "=== JStack Automated Response Status ==="
    echo ""
    
    echo "Active IP Blocks:"
    if [[ -f "$BLOCKED_IPS_FILE" ]]; then
        local block_count=$(grep -c "deny" "$BLOCKED_IPS_FILE" 2>/dev/null || echo "0")
        echo "  Total active blocks: $block_count"
        if [[ $block_count -gt 0 ]]; then
            echo "  Recent blocks:"
            tail -5 "$BLOCKED_IPS_FILE" | grep "deny" | while read -r line; do
                echo "    $line"
            done
        fi
    else
        echo "  No active blocks"
    fi
    
    echo ""
    echo "Recent Response Actions:"
    if [[ -f "$RESPONSE_LOG" ]]; then
        tail -10 "$RESPONSE_LOG"
    else
        echo "  No response log found"
    fi
}

# Main function
main() {
    case "${1:-status}" in
        "block-ip") block_ip "$2" "$3" "$4" ;;
        "unblock-ip") unblock_ip "$2" "$3" ;;
        "escalate") escalate_incident "$2" "$3" "$4" ;;
        "cleanup") clean_expired_blocks ;;
        "status") show_status ;;
        "notify") send_security_notification "$2" "$3" ;;
        *) echo "Usage: $0 [block-ip|unblock-ip|escalate|cleanup|status|notify]"
           echo "  block-ip <ip> <reason> <duration>     - Block an IP address"
           echo "  unblock-ip <ip> <reason>              - Unblock an IP address"
           echo "  escalate <ip> <threats> <severity>    - Escalate an incident"
           echo "  cleanup                               - Clean expired blocks"
           echo "  status                                - Show current status"
           echo "  notify <subject> <message>            - Send notification"
           ;;
    esac
}

main "$@"
EOF
    
    safe_mv "/tmp/automated-response.sh" "$threat_dir/automated-response.sh" "Install automated response"
    execute_cmd "chmod +x $threat_dir/automated-response.sh" "Make response script executable"
}

create_incident_management_system() {
    local threat_dir="$1"
    
    log_info "Creating incident management system"
    
    cat > /tmp/incident-manager.sh << 'EOF'
#!/bin/bash
# Incident Management System for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

INCIDENT_DB="${BASE_DIR}/security/incidents.db"
INCIDENT_LOG="${BASE_DIR}/logs/security/incidents.log"

# Ensure directories exist
mkdir -p "$(dirname "$INCIDENT_DB")"
mkdir -p "$(dirname "$INCIDENT_LOG")"

# Initialize incident database (simple file-based)
init_incident_db() {
    if [[ ! -f "$INCIDENT_DB" ]]; then
        cat > "$INCIDENT_DB" << 'DB_EOF'
# JStack Stack Incident Database
# Format: TIMESTAMP|INCIDENT_ID|IP|TYPE|SEVERITY|STATUS|DESCRIPTION
DB_EOF
        log_info "Incident database initialized: $INCIDENT_DB"
    fi
}

# Create new incident
create_incident() {
    local ip="$1"
    local type="$2"
    local severity="$3"
    local description="$4"
    
    init_incident_db
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local incident_id="INC-$(date '+%Y%m%d%H%M%S')-$(shuf -i 1000-9999 -n 1)"
    
    echo "${timestamp}|${incident_id}|${ip}|${type}|${severity}|OPEN|${description}" >> "$INCIDENT_DB"
    echo "[$timestamp] CREATED incident $incident_id: $ip - $type ($severity) - $description" >> "$INCIDENT_LOG"
    
    log_info "Created incident: $incident_id"
    echo "$incident_id"
}

# Update incident status
update_incident() {
    local incident_id="$1"
    local new_status="$2"
    local notes="${3:-}"
    
    if [[ ! -f "$INCIDENT_DB" ]]; then
        log_error "Incident database not found"
        return 1
    fi
    
    local temp_file="/tmp/incidents_update.db"
    local updated=false
    
    while IFS='|' read -r timestamp id ip type severity status description; do
        if [[ "$id" == "$incident_id" ]]; then
            local update_time=$(date '+%Y-%m-%d %H:%M:%S')
            echo "${timestamp}|${id}|${ip}|${type}|${severity}|${new_status}|${description} [Updated: $update_time - $notes]"
            echo "[$update_time] UPDATED incident $incident_id: $status -> $new_status ($notes)" >> "$INCIDENT_LOG"
            updated=true
        else
            echo "${timestamp}|${id}|${ip}|${type}|${severity}|${status}|${description}"
        fi
    done < "$INCIDENT_DB" > "$temp_file"
    
    if [[ "$updated" == "true" ]]; then
        mv "$temp_file" "$INCIDENT_DB"
        log_success "Updated incident $incident_id to $new_status"
    else
        rm -f "$temp_file"
        log_error "Incident $incident_id not found"
        return 1
    fi
}

# List incidents
list_incidents() {
    local status_filter="${1:-all}"
    local limit="${2:-20}"
    
    if [[ ! -f "$INCIDENT_DB" ]]; then
        log_info "No incident database found"
        return 0
    fi
    
    echo "=== JStack Stack Security Incidents ==="
    echo ""
    
    local header="TIMESTAMP           | INCIDENT ID      | IP ADDRESS      | TYPE           | SEVERITY | STATUS"
    echo "$header"
    echo "$(echo "$header" | sed 's/./=/g')"
    
    local count=0
    while IFS='|' read -r timestamp id ip type severity status description; do
        # Skip header line
        if [[ "$timestamp" =~ ^#.* ]] || [[ -z "$timestamp" ]]; then
            continue
        fi
        
        # Filter by status if specified
        if [[ "$status_filter" != "all" && "$status" != "${status_filter^^}" ]]; then
            continue
        fi
        
        printf "%-19s | %-15s | %-15s | %-13s | %-8s | %s\n" \
            "$timestamp" "$id" "$ip" "$type" "$severity" "$status"
        
        ((count++))
        if [[ $count -ge $limit ]]; then
            break
        fi
    done < "$INCIDENT_DB"
    
    echo ""
    echo "Total incidents shown: $count"
    if [[ "$status_filter" != "all" ]]; then
        echo "Filter: Status = $status_filter"
    fi
}

# Get incident details
get_incident() {
    local incident_id="$1"
    
    if [[ ! -f "$INCIDENT_DB" ]]; then
        log_error "Incident database not found"
        return 1
    fi
    
    local incident_line=$(grep "|$incident_id|" "$INCIDENT_DB")
    if [[ -z "$incident_line" ]]; then
        log_error "Incident $incident_id not found"
        return 1
    fi
    
    IFS='|' read -r timestamp id ip type severity status description <<< "$incident_line"
    
    echo "=== Incident Details ==="
    echo "ID: $id"
    echo "Timestamp: $timestamp"
    echo "IP Address: $ip"
    echo "Type: $type"
    echo "Severity: $severity"
    echo "Status: $status"
    echo "Description: $description"
    echo ""
    
    # Show related log entries
    echo "=== Related Log Entries ==="
    grep "$ip\|$id" "$INCIDENT_LOG" 2>/dev/null | tail -10 || echo "No related logs found"
}

# Generate incident report
generate_report() {
    local period="${1:-24h}"
    local report_file="${BASE_DIR}/logs/security/incident-report-$(date +%Y%m%d_%H%M%S).txt"
    
    init_incident_db
    
    {
        echo "JStack Stack Security Incident Report"
        echo "Generated: $(date)"
        echo "Period: Last $period"
        echo "======================================="
        echo ""
        
        # Summary statistics
        echo "=== Summary ==="
        local total_incidents=$(grep -v "^#" "$INCIDENT_DB" | wc -l)
        local open_incidents=$(grep "|OPEN|" "$INCIDENT_DB" 2>/dev/null | wc -l || echo "0")
        local closed_incidents=$(grep "|CLOSED|" "$INCIDENT_DB" 2>/dev/null | wc -l || echo "0")
        
        echo "Total incidents: $total_incidents"
        echo "Open incidents: $open_incidents"
        echo "Closed incidents: $closed_incidents"
        echo ""
        
        # Severity breakdown
        echo "=== By Severity ==="
        local severities=("CRITICAL" "HIGH" "MEDIUM" "LOW")
        for sev in "${severities[@]}"; do
            local count=$(grep "|$sev|" "$INCIDENT_DB" 2>/dev/null | wc -l || echo "0")
            echo "$sev: $count"
        done
        echo ""
        
        # Top threat sources
        echo "=== Top 10 Threat Sources ==="
        grep -v "^#" "$INCIDENT_DB" | cut -d'|' -f3 | sort | uniq -c | sort -nr | head -10
        echo ""
        
        # Recent incidents
        echo "=== Recent Incidents ==="
        tail -20 "$INCIDENT_DB" | grep -v "^#"
        
    } > "$report_file"
    
    log_success "Incident report generated: $report_file"
    echo "$report_file"
}

# Auto-escalate incidents based on patterns
auto_escalate() {
    log_info "Running auto-escalation checks"
    
    if [[ ! -f "$INCIDENT_DB" ]]; then
        return 0
    fi
    
    # Check for multiple incidents from same IP
    grep -v "^#" "$INCIDENT_DB" | grep "|OPEN|" | cut -d'|' -f3 | sort | uniq -c | sort -nr | \
        while read count ip; do
            if [[ $count -ge 3 ]]; then
                log_warning "IP $ip has $count open incidents - escalating"
                
                # Create escalation incident
                local escalation_id=$(create_incident "$ip" "AUTO_ESCALATION" "HIGH" \
                    "Auto-escalated: $count open incidents from same IP")
                
                # Trigger automated response
                bash "$(dirname "$0")/automated-response.sh" escalate "$ip" "multiple-incidents" "HIGH" &
            fi
        done
}

# Main function
main() {
    case "${1:-list}" in
        "create") create_incident "$2" "$3" "$4" "$5" ;;
        "update") update_incident "$2" "$3" "$4" ;;
        "list") list_incidents "$2" "$3" ;;
        "get") get_incident "$2" ;;
        "report") generate_report "$2" ;;
        "escalate") auto_escalate ;;
        "init") init_incident_db ;;
        *) echo "Usage: $0 [create|update|list|get|report|escalate|init]"
           echo "  create <ip> <type> <severity> <desc>  - Create new incident"
           echo "  update <id> <status> <notes>          - Update incident status"
           echo "  list [status] [limit]                 - List incidents"
           echo "  get <incident_id>                     - Get incident details"
           echo "  report [period]                       - Generate report"
           echo "  escalate                              - Auto-escalate incidents"
           echo "  init                                  - Initialize database"
           ;;
    esac
}

main "$@"
EOF
    
    safe_mv "/tmp/incident-manager.sh" "$threat_dir/incident-manager.sh" "Install incident manager"
    execute_cmd "chmod +x $threat_dir/incident-manager.sh" "Make incident manager executable"
}

setup_threat_response_services() {
    local threat_dir="$1"
    
    log_info "Setting up threat response systemd services"
    
    # Threat detection service
    cat > /tmp/jarvis-threat-detection.service << EOF
[Unit]
Description=JStack Stack Threat Detection Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$threat_dir/threat-detector.sh detect
Restart=always
RestartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    execute_cmd "sudo mv /tmp/jarvis-threat-detection.service /etc/systemd/system/" "Install threat detection service"
    
    # Response cleanup timer
    cat > /tmp/jarvis-response-cleanup.service << EOF
[Unit]
Description=JStack Stack Response Cleanup
After=network.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$threat_dir/automated-response.sh cleanup
EOF
    
    cat > /tmp/jarvis-response-cleanup.timer << 'EOF'
[Unit]
Description=Run JStack response cleanup every hour
Requires=jarvis-response-cleanup.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    execute_cmd "sudo mv /tmp/jarvis-response-cleanup.service /etc/systemd/system/" "Install cleanup service"
    execute_cmd "sudo mv /tmp/jarvis-response-cleanup.timer /etc/systemd/system/" "Install cleanup timer"
    
    # Incident auto-escalation timer
    cat > /tmp/jarvis-incident-escalation.service << EOF
[Unit]
Description=JStack Stack Incident Auto-Escalation
After=network.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$threat_dir/incident-manager.sh escalate
EOF
    
    cat > /tmp/jarvis-incident-escalation.timer << 'EOF'
[Unit]
Description=Run JStack incident escalation every 30 minutes
Requires=jarvis-incident-escalation.service

[Timer]
OnCalendar=*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    execute_cmd "sudo mv /tmp/jarvis-incident-escalation.service /etc/systemd/system/" "Install escalation service"
    execute_cmd "sudo mv /tmp/jarvis-incident-escalation.timer /etc/systemd/system/" "Install escalation timer"
    
    # Reload systemd and enable services
    execute_cmd "sudo systemctl daemon-reload" "Reload systemd"
    execute_cmd "sudo systemctl enable jarvis-threat-detection" "Enable threat detection"
    execute_cmd "sudo systemctl enable jarvis-response-cleanup.timer" "Enable cleanup timer"
    execute_cmd "sudo systemctl enable jarvis-incident-escalation.timer" "Enable escalation timer"
}

# Main function
main() {
    case "${1:-setup}" in
        "setup") setup_threat_response ;;
        "start")
            sudo systemctl start jarvis-threat-detection 2>/dev/null || log_warning "Could not start threat detection"
            sudo systemctl start jarvis-response-cleanup.timer 2>/dev/null || log_warning "Could not start cleanup timer"
            sudo systemctl start jarvis-incident-escalation.timer 2>/dev/null || log_warning "Could not start escalation timer"
            ;;
        "stop")
            sudo systemctl stop jarvis-threat-detection 2>/dev/null || log_warning "Could not stop threat detection"
            sudo systemctl stop jarvis-response-cleanup.timer 2>/dev/null || log_warning "Could not stop cleanup timer"
            sudo systemctl stop jarvis-incident-escalation.timer 2>/dev/null || log_warning "Could not stop escalation timer"
            ;;
        "status")
            echo "=== Threat Response Services Status ==="
            systemctl status jarvis-threat-detection 2>/dev/null | head -5 || echo "Threat detection: Not running"
            systemctl status jarvis-response-cleanup.timer 2>/dev/null | head -3 || echo "Cleanup timer: Not running"
            systemctl status jarvis-incident-escalation.timer 2>/dev/null | head -3 || echo "Escalation timer: Not running"
            ;;
        *) echo "Usage: $0 [setup|start|stop|status]"
           echo "Automated threat response system for JStack Stack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi