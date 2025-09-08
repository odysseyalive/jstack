#!/bin/bash
# Security Monitoring & Alerting System for jstack
# Implements centralized logging, event correlation, metrics dashboard, and compliance monitoring

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 CENTRALIZED LOGGING AND EVENT CORRELATION
# ═══════════════════════════════════════════════════════════════════════════════

setup_centralized_logging() {
    log_section "Setting up Centralized Security Logging System"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup centralized security logging"
        return 0
    fi
    
    start_section_timer "Centralized Logging"
    
    local monitoring_dir="$BASE_DIR/security/monitoring"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $monitoring_dir/logs" "Create monitoring logs directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $monitoring_dir/correlation" "Create correlation directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $monitoring_dir/dashboards" "Create dashboards directory"
    
    # Create centralized log aggregator
    create_log_aggregator "$monitoring_dir"
    
    # Create event correlation engine
    create_event_correlation_engine "$monitoring_dir"
    
    # Set up log rotation and retention
    setup_log_management "$monitoring_dir"
    
    end_section_timer "Centralized Logging"
    log_success "Centralized logging system configured"
}

create_log_aggregator() {
    local monitoring_dir="$1"
    
    log_info "Creating centralized log aggregation system"
    
    cat > /tmp/log-aggregator.sh << 'EOF'
#!/bin/bash
# Centralized Log Aggregator for jstack Security Events

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Configuration
CENTRAL_LOG="${BASE_DIR}/security/monitoring/logs/security-events.log"
CORRELATION_LOG="${BASE_DIR}/security/monitoring/logs/correlation-events.log"
METRICS_LOG="${BASE_DIR}/security/monitoring/logs/security-metrics.log"

# Log sources
FAIL2BAN_LOG="/var/log/fail2ban.log"
NGINX_ACCESS_LOG="${BASE_DIR}/logs/nginx/access.log"
NGINX_ERROR_LOG="${BASE_DIR}/logs/nginx/error.log"
WAF_LOG="${BASE_DIR}/logs/nginx/waf-blocks.log"
THREAT_LOG="${BASE_DIR}/logs/security/threats.log"
INCIDENT_LOG="${BASE_DIR}/logs/security/incidents.log"

# Ensure directories exist
mkdir -p "$(dirname "$CENTRAL_LOG")"
mkdir -p "$(dirname "$CORRELATION_LOG")"
mkdir -p "$(dirname "$METRICS_LOG")"

# Standardized log format: TIMESTAMP|SOURCE|LEVEL|IP|EVENT_TYPE|DETAILS
log_security_event() {
    local source="$1"
    local level="$2"
    local ip="$3"
    local event_type="$4"
    local details="$5"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "${timestamp}|${source}|${level}|${ip}|${event_type}|${details}" >> "$CENTRAL_LOG"
}

# Process fail2ban logs
process_fail2ban_logs() {
    if [[ -f "$FAIL2BAN_LOG" ]]; then
        local last_processed=$(tail -1 /tmp/fail2ban_last_line 2>/dev/null || echo "0")
        local current_lines=$(wc -l < "$FAIL2BAN_LOG")
        
        if [[ $current_lines -gt $last_processed ]]; then
            tail -n +$((last_processed + 1)) "$FAIL2BAN_LOG" | while IFS= read -r line; do
                if [[ "$line" =~ ([0-9-]+\ [0-9:]+).*Ban\ ([0-9.]+) ]]; then
                    local timestamp="${BASH_REMATCH[1]}"
                    local ip="${BASH_REMATCH[2]}"
                    log_security_event "fail2ban" "HIGH" "$ip" "IP_BANNED" "Automatic ban by fail2ban"
                elif [[ "$line" =~ ([0-9-]+\ [0-9:]+).*Unban\ ([0-9.]+) ]]; then
                    local timestamp="${BASH_REMATCH[1]}"
                    local ip="${BASH_REMATCH[2]}"
                    log_security_event "fail2ban" "INFO" "$ip" "IP_UNBANNED" "Automatic unban by fail2ban"
                fi
            done
            echo "$current_lines" > /tmp/fail2ban_last_line
        fi
    fi
}

# Process NGINX access logs for security events
process_nginx_access_logs() {
    if [[ -f "$NGINX_ACCESS_LOG" ]]; then
        local last_processed=$(tail -1 /tmp/nginx_access_last_line 2>/dev/null || echo "0")
        local current_lines=$(wc -l < "$NGINX_ACCESS_LOG")
        
        if [[ $current_lines -gt $last_processed ]]; then
            tail -n +$((last_processed + 1)) "$NGINX_ACCESS_LOG" | while IFS= read -r line; do
                # Extract IP, status code, and request
                if [[ "$line" =~ ([0-9.]+).*\"[A-Z]+\ ([^\"]+)\"\ ([0-9]+) ]]; then
                    local ip="${BASH_REMATCH[1]}"
                    local request="${BASH_REMATCH[2]}"
                    local status="${BASH_REMATCH[3]}"
                    
                    # Log security-relevant events
                    case "$status" in
                        "401"|"403")
                            log_security_event "nginx" "MEDIUM" "$ip" "UNAUTHORIZED_ACCESS" "Status: $status Request: $request"
                            ;;
                        "429")
                            log_security_event "nginx" "MEDIUM" "$ip" "RATE_LIMITED" "Rate limit exceeded: $request"
                            ;;
                        "404")
                            if [[ "$request" =~ (\.php|\.asp|wp-admin|admin|\.env) ]]; then
                                log_security_event "nginx" "LOW" "$ip" "SUSPICIOUS_REQUEST" "404 on suspicious path: $request"
                            fi
                            ;;
                    esac
                fi
            done
            echo "$current_lines" > /tmp/nginx_access_last_line
        fi
    fi
}

# Process WAF logs
process_waf_logs() {
    if [[ -f "$WAF_LOG" ]]; then
        local last_processed=$(tail -1 /tmp/waf_last_line 2>/dev/null || echo "0")
        local current_lines=$(wc -l < "$WAF_LOG")
        
        if [[ $current_lines -gt $last_processed ]]; then
            tail -n +$((last_processed + 1)) "$WAF_LOG" | while IFS= read -r line; do
                if [[ "$line" =~ ([0-9.]+).*\"([^\"]+)\" ]]; then
                    local ip="${BASH_REMATCH[1]}"
                    local request="${BASH_REMATCH[2]}"
                    
                    # Classify WAF blocks by severity
                    local severity="MEDIUM"
                    local attack_type="WAF_BLOCK"
                    
                    if [[ "$request" =~ (union|select|script|javascript) ]]; then
                        severity="HIGH"
                        attack_type="SQL_XSS_ATTEMPT"
                    elif [[ "$request" =~ (\.\./|%00|cmd|exec) ]]; then
                        severity="HIGH"
                        attack_type="INJECTION_ATTEMPT"
                    fi
                    
                    log_security_event "waf" "$severity" "$ip" "$attack_type" "Blocked request: $request"
                fi
            done
            echo "$current_lines" > /tmp/waf_last_line
        fi
    fi
}

# Process threat detection logs
process_threat_logs() {
    if [[ -f "$THREAT_LOG" ]]; then
        local last_processed=$(tail -1 /tmp/threat_last_line 2>/dev/null || echo "0")
        local current_lines=$(wc -l < "$THREAT_LOG")
        
        if [[ $current_lines -gt $last_processed ]]; then
            tail -n +$((last_processed + 1)) "$THREAT_LOG" | while IFS= read -r line; do
                if [[ "$line" =~ \[(.*)\]\ \[(.*)\]\ IP=(.*)\ TYPE=(.*)\ DETAILS=(.*) ]]; then
                    local timestamp="${BASH_REMATCH[1]}"
                    local level="${BASH_REMATCH[2]}"
                    local ip="${BASH_REMATCH[3]}"
                    local type="${BASH_REMATCH[4]}"
                    local details="${BASH_REMATCH[5]}"
                    
                    log_security_event "threat-detector" "$level" "$ip" "$type" "$details"
                fi
            done
            echo "$current_lines" > /tmp/threat_last_line
        fi
    fi
}

# Generate security metrics
generate_security_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hour_ago=$(date -d '1 hour ago' '+%Y-%m-%d %H:%M:%S')
    
    # Count events in the last hour
    local banned_ips=$(grep "$hour_ago" "$CENTRAL_LOG" 2>/dev/null | grep "IP_BANNED" | wc -l || echo "0")
    local waf_blocks=$(grep "$hour_ago" "$CENTRAL_LOG" 2>/dev/null | grep "WAF_BLOCK" | wc -l || echo "0")
    local rate_limits=$(grep "$hour_ago" "$CENTRAL_LOG" 2>/dev/null | grep "RATE_LIMITED" | wc -l || echo "0")
    local unauthorized=$(grep "$hour_ago" "$CENTRAL_LOG" 2>/dev/null | grep "UNAUTHORIZED_ACCESS" | wc -l || echo "0")
    
    # Log metrics
    echo "${timestamp}|METRICS|INFO|SYSTEM|HOURLY_STATS|banned_ips:${banned_ips},waf_blocks:${waf_blocks},rate_limits:${rate_limits},unauthorized:${unauthorized}" >> "$METRICS_LOG"
}

# Main aggregation workflow
aggregate_logs() {
    log_info "Starting log aggregation cycle"
    
    process_fail2ban_logs
    process_nginx_access_logs
    process_waf_logs
    process_threat_logs
    
    # Generate metrics every hour
    local current_minute=$(date '+%M')
    if [[ "$current_minute" == "00" ]]; then
        generate_security_metrics
    fi
    
    log_info "Log aggregation cycle completed"
}

# Display recent security events
show_recent_events() {
    local count="${1:-20}"
    
    echo "=== Recent Security Events (Last $count) ==="
    if [[ -f "$CENTRAL_LOG" ]]; then
        tail -n "$count" "$CENTRAL_LOG" | while IFS='|' read -r timestamp source level ip event_type details; do
            case "$level" in
                "CRITICAL"|"HIGH") echo "🔴 $timestamp [$level] $source: $ip - $event_type ($details)" ;;
                "MEDIUM") echo "🟡 $timestamp [$level] $source: $ip - $event_type ($details)" ;;
                "LOW"|"INFO") echo "🟢 $timestamp [$level] $source: $ip - $event_type ($details)" ;;
                *) echo "⚪ $timestamp [$level] $source: $ip - $event_type ($details)" ;;
            esac
        done
    else
        echo "No security events log found"
    fi
}

# Main function
case "${1:-aggregate}" in
    "aggregate") aggregate_logs ;;
    "metrics") generate_security_metrics ;;
    "events") show_recent_events "$2" ;;
    "fail2ban") process_fail2ban_logs ;;
    "nginx") process_nginx_access_logs ;;
    "waf") process_waf_logs ;;
    "threats") process_threat_logs ;;
    *) echo "Usage: $0 [aggregate|metrics|events|fail2ban|nginx|waf|threats]"
       echo "Centralized log aggregation for jstack security" ;;
esac
EOF
    
    safe_mv "/tmp/log-aggregator.sh" "$monitoring_dir/log-aggregator.sh" "Install log aggregator"
    execute_cmd "chmod +x $monitoring_dir/log-aggregator.sh" "Make log aggregator executable"
}

create_event_correlation_engine() {
    local monitoring_dir="$1"
    
    log_info "Creating event correlation engine"
    
    cat > /tmp/event-correlator.sh << 'EOF'
#!/bin/bash
# Event Correlation Engine for jstack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

CENTRAL_LOG="${BASE_DIR}/security/monitoring/logs/security-events.log"
CORRELATION_LOG="${BASE_DIR}/security/monitoring/logs/correlation-events.log"
ALERT_LOG="${BASE_DIR}/security/monitoring/logs/security-alerts.log"

# Correlation rules and thresholds
MULTI_SOURCE_THRESHOLD=3    # Same IP from 3+ sources
TIME_WINDOW=300            # 5 minutes
ATTACK_BURST_THRESHOLD=10  # 10 events in time window
CRITICAL_EVENT_THRESHOLD=5  # 5 critical events

log_correlation() {
    local correlation_type="$1"
    local severity="$2"
    local details="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "${timestamp}|CORRELATION|${severity}|SYSTEM|${correlation_type}|${details}" >> "$CORRELATION_LOG"
    
    # Log alerts for high/critical correlations
    if [[ "$severity" =~ ^(HIGH|CRITICAL)$ ]]; then
        echo "${timestamp}|ALERT|${severity}|${correlation_type}|${details}" >> "$ALERT_LOG"
    fi
}

# Detect coordinated attacks from multiple IPs
detect_coordinated_attacks() {
    local time_cutoff=$(date -d "$TIME_WINDOW seconds ago" '+%Y-%m-%d %H:%M:%S')
    
    if [[ -f "$CENTRAL_LOG" ]]; then
        # Find IPs with multiple attack types in time window
        grep -E "(WAF_BLOCK|INJECTION_ATTEMPT|SQL_XSS_ATTEMPT)" "$CENTRAL_LOG" | \
        awk -F'|' -v cutoff="$time_cutoff" '$1 > cutoff {print $4}' | \
        sort | uniq -c | sort -nr | \
        while read count ip; do
            if [[ $count -ge $ATTACK_BURST_THRESHOLD ]]; then
                log_correlation "COORDINATED_ATTACK" "HIGH" "IP $ip: $count attacks in ${TIME_WINDOW}s"
                
                # Trigger response
                bash "$(dirname "$0")/../threat-response/automated-response.sh" block-ip "$ip" "coordinated-attack" 7200 &
            fi
        done
    fi
}

# Detect multi-source attacks (same IP across different sources)
detect_multi_source_attacks() {
    local time_cutoff=$(date -d "$TIME_WINDOW seconds ago" '+%Y-%m-%d %H:%M:%S')
    
    if [[ -f "$CENTRAL_LOG" ]]; then
        # Group by IP and count unique sources
        awk -F'|' -v cutoff="$time_cutoff" '$1 > cutoff && $4 != "SYSTEM" {print $4 "|" $2}' "$CENTRAL_LOG" | \
        sort -u | cut -d'|' -f1 | sort | uniq -c | sort -nr | \
        while read count ip; do
            if [[ $count -ge $MULTI_SOURCE_THRESHOLD ]]; then
                local sources=$(awk -F'|' -v cutoff="$time_cutoff" -v ip="$ip" '$1 > cutoff && $4 == ip {print $2}' "$CENTRAL_LOG" | sort -u | tr '\n' ',' | sed 's/,$//')
                log_correlation "MULTI_SOURCE_ATTACK" "CRITICAL" "IP $ip detected by $count sources: $sources"
                
                # Create incident
                bash "$(dirname "$0")/../threat-response/incident-manager.sh" create "$ip" "MULTI_SOURCE" "CRITICAL" "Detected by multiple sources: $sources" &
            fi
        done
    fi
}

# Detect privilege escalation patterns
detect_privilege_escalation() {
    local time_cutoff=$(date -d "3600 seconds ago" '+%Y-%m-%d %H:%M:%S')  # 1 hour window
    
    if [[ -f "$CENTRAL_LOG" ]]; then
        # Look for escalating attack patterns: 404 scanning -> 401/403 -> WAF blocks
        awk -F'|' -v cutoff="$time_cutoff" '$1 > cutoff {print $4 "|" $5}' "$CENTRAL_LOG" | \
        sort | \
        awk -F'|' '{
            ip = $1
            event = $2
            if (event ~ /SUSPICIOUS_REQUEST/) scanning[ip]++
            if (event ~ /UNAUTHORIZED_ACCESS/) auth[ip]++
            if (event ~ /(WAF_BLOCK|INJECTION_ATTEMPT)/) injection[ip]++
        } END {
            for (ip in scanning) {
                if (scanning[ip] >= 5 && auth[ip] >= 2 && injection[ip] >= 1) {
                    print ip "|" scanning[ip] "|" auth[ip] "|" injection[ip]
                }
            }
        }' | \
        while IFS='|' read ip scan_count auth_count inject_count; do
            log_correlation "PRIVILEGE_ESCALATION" "HIGH" "IP $ip: scanning($scan_count) -> auth($auth_count) -> injection($inject_count)"
            
            # Extended block for escalation attempts
            bash "$(dirname "$0")/../threat-response/automated-response.sh" block-ip "$ip" "privilege-escalation" 14400 &
        done
    fi
}

# Detect anomalous traffic patterns
detect_traffic_anomalies() {
    local hour_ago=$(date -d '1 hour ago' '+%Y-%m-%d %H:%M:%S')
    
    if [[ -f "$CENTRAL_LOG" ]]; then
        # Calculate request volume anomalies
        local current_hour_events=$(awk -F'|' -v cutoff="$hour_ago" '$1 > cutoff' "$CENTRAL_LOG" | wc -l)
        local avg_events=100  # Baseline - should be calculated from historical data
        
        if [[ $current_hour_events -gt $((avg_events * 3)) ]]; then
            log_correlation "TRAFFIC_ANOMALY" "MEDIUM" "Traffic spike: $current_hour_events events (avg: $avg_events)"
        fi
        
        # Detect unusual geographic patterns (if available)
        # This would require GeoIP integration
    fi
}

# Generate correlation report
generate_correlation_report() {
    local report_file="${BASE_DIR}/security/monitoring/logs/correlation-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "jstack Security Event Correlation Report"
        echo "Generated: $(date)"
        echo "=============================================="
        echo ""
        
        echo "=== Active Correlations (Last 24h) ==="
        if [[ -f "$CORRELATION_LOG" ]]; then
            grep "$(date -d '24 hours ago' '+%Y-%m-%d')" "$CORRELATION_LOG" | tail -20 || echo "No correlations found"
        fi
        echo ""
        
        echo "=== Security Alerts (Last 24h) ==="
        if [[ -f "$ALERT_LOG" ]]; then
            grep "$(date -d '24 hours ago' '+%Y-%m-%d')" "$ALERT_LOG" | tail -20 || echo "No alerts found"
        fi
        echo ""
        
        echo "=== Top Threat IPs ==="
        if [[ -f "$CENTRAL_LOG" ]]; then
            grep "$(date -d '24 hours ago' '+%Y-%m-%d')" "$CENTRAL_LOG" | \
            awk -F'|' '$3 ~ /(HIGH|CRITICAL)/ {print $4}' | \
            sort | uniq -c | sort -nr | head -10 || echo "No threats found"
        fi
        
    } > "$report_file"
    
    log_success "Correlation report generated: $report_file"
}

# Main correlation workflow
run_correlation() {
    log_info "Starting event correlation analysis"
    
    detect_coordinated_attacks
    detect_multi_source_attacks
    detect_privilege_escalation
    detect_traffic_anomalies
    
    log_info "Event correlation analysis completed"
}

# Show correlation dashboard
show_dashboard() {
    echo "=== jstack Security Correlation Dashboard ==="
    echo "Last updated: $(date)"
    echo ""
    
    # Active alerts
    echo "🚨 Active Alerts (Last Hour):"
    if [[ -f "$ALERT_LOG" ]]; then
        local alerts=$(grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')" "$ALERT_LOG" | wc -l || echo "0")
        echo "   Total alerts: $alerts"
        if [[ $alerts -gt 0 ]]; then
            echo "   Recent alerts:"
            tail -5 "$ALERT_LOG" | while IFS='|' read timestamp level severity type details; do
                echo "   - $timestamp [$severity] $type: $details"
            done
        fi
    else
        echo "   No alerts log found"
    fi
    echo ""
    
    # Correlation summary
    echo "🔗 Correlations (Last 24h):"
    if [[ -f "$CORRELATION_LOG" ]]; then
        local correlations=$(grep "$(date -d '24 hours ago' '+%Y-%m-%d')" "$CORRELATION_LOG" | wc -l || echo "0")
        echo "   Total correlations: $correlations"
        
        # Breakdown by type
        local coord_attacks=$(grep "COORDINATED_ATTACK" "$CORRELATION_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        local multi_source=$(grep "MULTI_SOURCE_ATTACK" "$CORRELATION_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        local escalation=$(grep "PRIVILEGE_ESCALATION" "$CORRELATION_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        
        echo "   - Coordinated attacks: $coord_attacks"
        echo "   - Multi-source attacks: $multi_source" 
        echo "   - Privilege escalation: $escalation"
    else
        echo "   No correlations log found"
    fi
}

# Main function
case "${1:-correlate}" in
    "correlate") run_correlation ;;
    "coordinated") detect_coordinated_attacks ;;
    "multi-source") detect_multi_source_attacks ;;
    "escalation") detect_privilege_escalation ;;
    "anomalies") detect_traffic_anomalies ;;
    "report") generate_correlation_report ;;
    "dashboard") show_dashboard ;;
    *) echo "Usage: $0 [correlate|coordinated|multi-source|escalation|anomalies|report|dashboard]"
       echo "Event correlation engine for jstack security" ;;
esac
EOF
    
    safe_mv "/tmp/event-correlator.sh" "$monitoring_dir/event-correlator.sh" "Install event correlator"
    execute_cmd "chmod +x $monitoring_dir/event-correlator.sh" "Make event correlator executable"
}

setup_log_management() {
    local monitoring_dir="$1"
    
    log_info "Setting up log rotation and retention"
    
    # Create logrotate configuration
    cat > /tmp/jstack-security-logs << EOF
# Logrotate configuration for jstack security logs
$BASE_DIR/security/monitoring/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $SERVICE_USER $SERVICE_GROUP
    postrotate
        /bin/kill -HUP \$(cat /var/run/rsyslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}

$BASE_DIR/logs/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 $SERVICE_USER $SERVICE_GROUP
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            /bin/kill -USR1 \$(cat /var/run/nginx.pid)
        fi
    endscript
}
EOF
    
    execute_cmd "sudo mv /tmp/jstack-security-logs /etc/logrotate.d/jstack-security-logs" "Install logrotate config"
}

# Main function
main() {
    case "${1:-setup}" in
        "logging") setup_centralized_logging ;;
        "setup") setup_centralized_logging ;;
        "test") 
            # Test logging components
            if [[ -f "$BASE_DIR/security/monitoring/log-aggregator.sh" ]]; then
                bash "$BASE_DIR/security/monitoring/log-aggregator.sh" events 10
            else
                log_warning "Log aggregator not found - run setup first"
            fi
            ;;
        *) echo "Usage: $0 [setup|logging|test]"
           echo "Security monitoring system for jstack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi