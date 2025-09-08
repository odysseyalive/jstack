#!/bin/bash
# Automated Security Alerting System for JStack
# Multi-channel alerting with intelligent escalation and notification management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 📢 MULTI-CHANNEL ALERTING SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

setup_alerting_system() {
    log_section "Setting up Multi-Channel Security Alerting System"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup multi-channel security alerting"
        return 0
    fi
    
    start_section_timer "Alerting Setup"
    
    local alerting_dir="$BASE_DIR/security/alerting"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $alerting_dir/channels" "Create alerting channels directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $alerting_dir/templates" "Create alert templates directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $alerting_dir/config" "Create alerting config directory"
    
    # Create alerting configuration
    create_alerting_config "$alerting_dir"
    
    # Create notification channels
    create_notification_channels "$alerting_dir"
    
    # Create alert templates
    create_alert_templates "$alerting_dir"
    
    # Create alert manager
    create_alert_manager "$alerting_dir"
    
    # Set up alerting services
    setup_alerting_services "$alerting_dir"
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$alerting_dir/" "Set alerting directory ownership"
    
    end_section_timer "Alerting Setup"
    log_success "Multi-channel alerting system configured"
}

create_alerting_config() {
    local alerting_dir="$1"
    
    log_info "Creating alerting system configuration"
    
    cat > /tmp/alerting-config.json << EOF
{
    "alerting": {
        "enabled": true,
        "channels": {
            "email": {
                "enabled": true,
                "addresses": ["${ALERT_EMAIL:-admin@${DOMAIN}}"],
                "smtp_server": "localhost",
                "smtp_port": 25,
                "severity_threshold": "MEDIUM"
            },
            "slack": {
                "enabled": ${SLACK_WEBHOOK:+true},
                "webhook_url": "${SLACK_WEBHOOK:-}",
                "channel": "#security-alerts",
                "username": "jstack-Security",
                "severity_threshold": "HIGH"
            },
            "webhook": {
                "enabled": false,
                "url": "",
                "method": "POST",
                "headers": {"Content-Type": "application/json"},
                "severity_threshold": "CRITICAL"
            },
            "syslog": {
                "enabled": true,
                "facility": "local0",
                "severity_threshold": "LOW"
            },
            "desktop": {
                "enabled": true,
                "severity_threshold": "HIGH"
            }
        },
        "escalation": {
            "enabled": true,
            "rules": [
                {
                    "condition": "severity == 'CRITICAL'",
                    "actions": ["email", "slack", "syslog", "desktop"],
                    "delay": 0
                },
                {
                    "condition": "severity == 'HIGH'",
                    "actions": ["email", "slack", "syslog"],
                    "delay": 60
                },
                {
                    "condition": "severity == 'MEDIUM'",
                    "actions": ["email", "syslog"],
                    "delay": 300
                },
                {
                    "condition": "severity == 'LOW'",
                    "actions": ["syslog"],
                    "delay": 900
                }
            ]
        },
        "rate_limiting": {
            "enabled": true,
            "max_alerts_per_minute": 10,
            "burst_threshold": 5,
            "cooldown_period": 300
        },
        "maintenance_windows": {
            "enabled": true,
            "windows": []
        }
    }
}
EOF
    
    safe_mv "/tmp/alerting-config.json" "$alerting_dir/config/alerting-config.json" "Install alerting config"
}

create_notification_channels() {
    local alerting_dir="$1"
    
    log_info "Creating notification channel handlers"
    
    # Email notification channel
    cat > /tmp/email-channel.sh << 'EOF'
#!/bin/bash
# Email Notification Channel for jstack

send_email_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local timestamp="$4"
    
    # Prepare email content
    local subject="[jstack-$severity] $title"
    local email_body="
jstack Security Alert

Severity: $severity
Time: $timestamp
Title: $title

Details:
$message

---
jstack Security Monitoring
$(hostname) - $(date)
"
    
    # Send via configured method
    if command -v mail >/dev/null 2>&1; then
        echo "$email_body" | mail -s "$subject" "$ALERT_EMAIL"
        return $?
    elif command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $ALERT_EMAIL"
            echo "Subject: $subject"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            echo "$email_body"
        } | sendmail "$ALERT_EMAIL"
        return $?
    else
        echo "No email sender available" >&2
        return 1
    fi
}

# Test email functionality
test_email() {
    send_email_alert "INFO" "Test Alert" "This is a test alert from jstack security system." "$(date)"
}

case "${1:-send}" in
    "send") send_email_alert "$2" "$3" "$4" "$5" ;;
    "test") test_email ;;
    *) echo "Usage: $0 [send|test]" ;;
esac
EOF
    
    safe_mv "/tmp/email-channel.sh" "$alerting_dir/channels/email-channel.sh" "Install email channel"
    execute_cmd "chmod +x $alerting_dir/channels/email-channel.sh" "Make email channel executable"
    
    # Slack notification channel
    cat > /tmp/slack-channel.sh << 'EOF'
#!/bin/bash
# Slack Notification Channel for jstack

send_slack_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local timestamp="$4"
    
    if [[ -z "$SLACK_WEBHOOK" ]]; then
        echo "Slack webhook not configured" >&2
        return 1
    fi
    
    # Set emoji and color based on severity
    local emoji color
    case "$severity" in
        "CRITICAL") emoji="🚨" color="danger" ;;
        "HIGH")     emoji="⚠️"  color="warning" ;;
        "MEDIUM")   emoji="🟡" color="good" ;;
        "LOW")      emoji="ℹ️"  color="#36a64f" ;;
        *)          emoji="📋" color="#36a64f" ;;
    esac
    
    # Prepare Slack payload
    local payload=$(cat << SLACK_EOF
{
    "username": "jstack-Security",
    "icon_emoji": ":shield:",
    "attachments": [
        {
            "color": "$color",
            "title": "$emoji jstack Security Alert - $severity",
            "title_link": "https://${DOMAIN}",
            "text": "$title",
            "fields": [
                {
                    "title": "Details",
                    "value": "$message",
                    "short": false
                },
                {
                    "title": "Timestamp",
                    "value": "$timestamp",
                    "short": true
                },
                {
                    "title": "Host",
                    "value": "$(hostname)",
                    "short": true
                }
            ],
            "footer": "jstack Security",
            "ts": $(date +%s)
        }
    ]
}
SLACK_EOF
)
    
    # Send to Slack
    if command -v curl >/dev/null 2>&1; then
        curl -X POST -H 'Content-type: application/json' \
             --data "$payload" \
             "$SLACK_WEBHOOK" \
             --silent --output /dev/null
        return $?
    else
        echo "curl not available for Slack notifications" >&2
        return 1
    fi
}

# Test Slack functionality
test_slack() {
    send_slack_alert "INFO" "Test Alert" "This is a test alert from jstack security system." "$(date)"
}

case "${1:-send}" in
    "send") send_slack_alert "$2" "$3" "$4" "$5" ;;
    "test") test_slack ;;
    *) echo "Usage: $0 [send|test]" ;;
esac
EOF
    
    safe_mv "/tmp/slack-channel.sh" "$alerting_dir/channels/slack-channel.sh" "Install Slack channel"
    execute_cmd "chmod +x $alerting_dir/channels/slack-channel.sh" "Make Slack channel executable"
    
    # Syslog notification channel
    cat > /tmp/syslog-channel.sh << 'EOF'
#!/bin/bash
# Syslog Notification Channel for jstack

send_syslog_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local timestamp="$4"
    
    # Map severity to syslog priority
    local priority
    case "$severity" in
        "CRITICAL") priority="crit" ;;
        "HIGH")     priority="err" ;;
        "MEDIUM")   priority="warning" ;;
        "LOW")      priority="info" ;;
        *)          priority="notice" ;;
    esac
    
    # Send to syslog
    logger -p local0.$priority -t jstack-security "[$severity] $title: $message"
    return $?
}

# Test syslog functionality
test_syslog() {
    send_syslog_alert "INFO" "Test Alert" "This is a test alert from jstack security system." "$(date)"
}

case "${1:-send}" in
    "send") send_syslog_alert "$2" "$3" "$4" "$5" ;;
    "test") test_syslog ;;
    *) echo "Usage: $0 [send|test]" ;;
esac
EOF
    
    safe_mv "/tmp/syslog-channel.sh" "$alerting_dir/channels/syslog-channel.sh" "Install syslog channel"
    execute_cmd "chmod +x $alerting_dir/channels/syslog-channel.sh" "Make syslog channel executable"
    
    # Desktop notification channel
    cat > /tmp/desktop-channel.sh << 'EOF'
#!/bin/bash
# Desktop Notification Channel for jstack

send_desktop_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local timestamp="$4"
    
    # Desktop notifications (if available)
    if command -v notify-send >/dev/null 2>&1; then
        # Set icon and urgency based on severity
        local urgency icon
        case "$severity" in
            "CRITICAL") urgency="critical" icon="dialog-error" ;;
            "HIGH")     urgency="critical" icon="dialog-warning" ;;
            "MEDIUM")   urgency="normal"   icon="dialog-information" ;;
            "LOW")      urgency="low"      icon="dialog-information" ;;
            *)          urgency="normal"   icon="dialog-information" ;;
        esac
        
        notify-send --urgency="$urgency" --icon="$icon" \
                   "jstack Security Alert ($severity)" \
                   "$title: $message"
        return $?
    else
        # Fallback to console bell and message
        echo -e "\a[jstack-$severity] $title: $message" >/dev/console 2>/dev/null || \
        echo -e "\a[jstack-$severity] $title: $message"
        return $?
    fi
}

# Test desktop functionality
test_desktop() {
    send_desktop_alert "INFO" "Test Alert" "This is a test alert from jstack security system." "$(date)"
}

case "${1:-send}" in
    "send") send_desktop_alert "$2" "$3" "$4" "$5" ;;
    "test") test_desktop ;;
    *) echo "Usage: $0 [send|test]" ;;
esac
EOF
    
    safe_mv "/tmp/desktop-channel.sh" "$alerting_dir/channels/desktop-channel.sh" "Install desktop channel"
    execute_cmd "chmod +x $alerting_dir/channels/desktop-channel.sh" "Make desktop channel executable"
}

create_alert_templates() {
    local alerting_dir="$1"
    
    log_info "Creating alert message templates"
    
    # IP Ban alert template
    cat > /tmp/ip-ban-template.txt << 'EOF'
🚫 IP Address Banned

An IP address has been automatically banned due to suspicious activity.

IP Address: {{IP}}
Reason: {{REASON}}
Duration: {{DURATION}}
Detection Method: {{METHOD}}
Attack Pattern: {{PATTERN}}

Recent Activity:
{{ACTIVITY}}

Action Taken:
- IP blocked in firewall
- Added to fail2ban banlist
- NGINX access denied

This is an automated response by jstack security system.
EOF
    
    safe_mv "/tmp/ip-ban-template.txt" "$alerting_dir/templates/ip-ban-template.txt" "Install IP ban template"
    
    # Security incident template
    cat > /tmp/security-incident-template.txt << 'EOF'
🚨 Security Incident Detected

A security incident has been detected and logged in the incident management system.

Incident ID: {{INCIDENT_ID}}
Severity: {{SEVERITY}}
Type: {{TYPE}}
Source IP: {{IP}}
Status: {{STATUS}}

Description:
{{DESCRIPTION}}

Timeline:
{{TIMELINE}}

Recommended Actions:
{{RECOMMENDATIONS}}

For detailed investigation, review the incident logs and consider escalating if necessary.
EOF
    
    safe_mv "/tmp/security-incident-template.txt" "$alerting_dir/templates/security-incident-template.txt" "Install incident template"
    
    # WAF attack template
    cat > /tmp/waf-attack-template.txt << 'EOF'
🛡️ Web Application Firewall Alert

The Web Application Firewall has detected and blocked a potential attack.

Attack Type: {{ATTACK_TYPE}}
Source IP: {{IP}}
Target: {{TARGET}}
Blocked Request: {{REQUEST}}
Detection Rule: {{RULE}}

Attack Details:
{{DETAILS}}

This attack has been automatically blocked. The source IP will be monitored for additional malicious activity.
EOF
    
    safe_mv "/tmp/waf-attack-template.txt" "$alerting_dir/templates/waf-attack-template.txt" "Install WAF attack template"
    
    # System health template
    cat > /tmp/system-health-template.txt << 'EOF'
📊 System Health Alert

A system health issue has been detected that may affect security posture.

Alert Type: {{ALERT_TYPE}}
Component: {{COMPONENT}}
Status: {{STATUS}}
Severity: {{SEVERITY}}

Details:
{{DETAILS}}

Impact Assessment:
{{IMPACT}}

Recommended Actions:
{{ACTIONS}}

Please investigate and resolve this issue promptly to maintain security effectiveness.
EOF
    
    safe_mv "/tmp/system-health-template.txt" "$alerting_dir/templates/system-health-template.txt" "Install system health template"
}

create_alert_manager() {
    local alerting_dir="$1"
    
    log_info "Creating alert management system"
    
    cat > /tmp/alert-manager.sh << 'EOF'
#!/bin/bash
# Alert Manager for jstack Security System

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Configuration
ALERTING_CONFIG="${BASE_DIR}/security/alerting/config/alerting-config.json"
ALERT_LOG="${BASE_DIR}/security/monitoring/logs/security-alerts.log"
RATE_LIMIT_FILE="/tmp/jarvis-alert-rate-limit"

# Rate limiting state
declare -A alert_counts
declare -A last_alert_time

# Load configuration
load_alerting_config() {
    if [[ -f "$ALERTING_CONFIG" && command -v jq >/dev/null 2>&1 ]]; then
        return 0
    else
        # Fallback to defaults
        return 1
    fi
}

# Check if alerting is in maintenance window
in_maintenance_window() {
    # Simple implementation - can be enhanced with JSON config
    return 1  # No maintenance window active
}

# Rate limiting check
check_rate_limit() {
    local alert_type="$1"
    local current_time=$(date +%s)
    local window_size=60  # 1 minute window
    local max_alerts=10   # Max alerts per minute
    
    # Clean old entries
    for key in "${!last_alert_time[@]}"; do
        if [[ $((current_time - last_alert_time[$key])) -gt $window_size ]]; then
            unset alert_counts[$key]
            unset last_alert_time[$key]
        fi
    done
    
    # Check current rate
    local count=${alert_counts[$alert_type]:-0}
    if [[ $count -ge $max_alerts ]]; then
        return 1  # Rate limited
    fi
    
    # Update counters
    alert_counts[$alert_type]=$((count + 1))
    last_alert_time[$alert_type]=$current_time
    
    return 0  # Not rate limited
}

# Get escalation channels for severity
get_escalation_channels() {
    local severity="$1"
    
    case "$severity" in
        "CRITICAL") echo "email slack syslog desktop" ;;
        "HIGH")     echo "email slack syslog" ;;
        "MEDIUM")   echo "email syslog" ;;
        "LOW")      echo "syslog" ;;
        *)          echo "syslog" ;;
    esac
}

# Send alert through channel
send_to_channel() {
    local channel="$1"
    local severity="$2"
    local title="$3"
    local message="$4"
    local timestamp="$5"
    
    local channel_script="$(dirname "$0")/channels/${channel}-channel.sh"
    
    if [[ -x "$channel_script" ]]; then
        "$channel_script" send "$severity" "$title" "$message" "$timestamp"
        return $?
    else
        log_warning "Channel script not found: $channel_script"
        return 1
    fi
}

# Process alert template
process_template() {
    local template_name="$1"
    local template_vars="$2"  # JSON string with variables
    
    local template_file="$(dirname "$0")/templates/${template_name}-template.txt"
    
    if [[ -f "$template_file" ]]; then
        local content=$(cat "$template_file")
        
        # Simple variable substitution (can be enhanced with jq)
        if [[ -n "$template_vars" ]]; then
            # Basic substitution - in production, use proper templating
            content=$(echo "$content" | sed 's/{{IP}}/192.168.1.100/g')  # Example
        fi
        
        echo "$content"
    else
        echo "Template not found: $template_name"
    fi
}

# Main alert sending function
send_alert() {
    local severity="$1"
    local title="$2"
    local message="$3"
    local alert_type="${4:-general}"
    local template="${5:-}"
    local template_vars="${6:-}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check maintenance window
    if in_maintenance_window; then
        log_info "Alert suppressed due to maintenance window: $title"
        return 0
    fi
    
    # Check rate limiting
    if ! check_rate_limit "$alert_type"; then
        log_warning "Alert rate limited: $alert_type"
        return 0
    fi
    
    # Process template if provided
    if [[ -n "$template" ]]; then
        message=$(process_template "$template" "$template_vars")
    fi
    
    # Log alert
    echo "${timestamp}|ALERT|${severity}|${alert_type}|${title}|${message}" >> "$ALERT_LOG"
    
    # Get channels for severity
    local channels
    channels=$(get_escalation_channels "$severity")
    
    # Send to each channel
    local success=0
    for channel in $channels; do
        if send_to_channel "$channel" "$severity" "$title" "$message" "$timestamp"; then
            log_info "Alert sent via $channel: $title"
            ((success++))
        else
            log_error "Failed to send alert via $channel: $title"
        fi
    done
    
    return $((success > 0 ? 0 : 1))
}

# Predefined alert functions
send_ip_ban_alert() {
    local ip="$1"
    local reason="$2"
    local duration="$3"
    
    local title="IP Address Banned: $ip"
    local message="IP $ip has been banned for $reason (duration: $duration seconds)"
    
    send_alert "HIGH" "$title" "$message" "ip-ban" "ip-ban" "{\"IP\":\"$ip\",\"REASON\":\"$reason\",\"DURATION\":\"$duration\"}"
}

send_security_incident_alert() {
    local incident_id="$1"
    local severity="$2"
    local incident_type="$3"
    local description="$4"
    
    local title="Security Incident: $incident_id"
    local message="Incident $incident_id ($incident_type) - $description"
    
    send_alert "$severity" "$title" "$message" "incident" "security-incident" "{\"INCIDENT_ID\":\"$incident_id\",\"TYPE\":\"$incident_type\"}"
}

send_waf_attack_alert() {
    local attack_type="$1"
    local ip="$2"
    local request="$3"
    
    local title="WAF Attack Blocked: $attack_type"
    local message="Blocked $attack_type from $ip: $request"
    
    send_alert "MEDIUM" "$title" "$message" "waf-attack" "waf-attack" "{\"ATTACK_TYPE\":\"$attack_type\",\"IP\":\"$ip\"}"
}

send_system_health_alert() {
    local component="$1"
    local status="$2"
    local details="$3"
    
    local title="System Health Alert: $component"
    local message="Component $component status: $status - $details"
    
    send_alert "MEDIUM" "$title" "$message" "system-health" "system-health" "{\"COMPONENT\":\"$component\",\"STATUS\":\"$status\"}"
}

# Test all notification channels
test_all_channels() {
    log_info "Testing all notification channels"
    
    local channels="email slack syslog desktop"
    for channel in $channels; do
        log_info "Testing $channel channel..."
        if send_to_channel "$channel" "INFO" "Test Alert" "This is a test of the $channel notification channel" "$(date)"; then
            log_success "$channel channel: OK"
        else
            log_error "$channel channel: FAILED"
        fi
    done
}

# Show alert statistics
show_alert_stats() {
    echo "=== jstack Alert Statistics ==="
    echo "Last updated: $(date)"
    echo ""
    
    if [[ -f "$ALERT_LOG" ]]; then
        echo "📊 Alert Summary (Last 24h):"
        local total_alerts=$(grep "$(date -d '24 hours ago' '+%Y-%m-%d')" "$ALERT_LOG" | wc -l || echo "0")
        echo "   Total alerts: $total_alerts"
        
        # Breakdown by severity
        local critical=$(grep "CRITICAL" "$ALERT_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        local high=$(grep "HIGH" "$ALERT_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        local medium=$(grep "MEDIUM" "$ALERT_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        local low=$(grep "LOW" "$ALERT_LOG" | grep "$(date '+%Y-%m-%d')" | wc -l || echo "0")
        
        echo "   - Critical: $critical"
        echo "   - High: $high"
        echo "   - Medium: $medium"
        echo "   - Low: $low"
        echo ""
        
        echo "📈 Recent Alerts:"
        tail -10 "$ALERT_LOG" | while IFS='|' read timestamp level severity type title message; do
            echo "   $timestamp [$severity] $title"
        done
    else
        echo "No alerts log found"
    fi
}

# Main function
case "${1:-send}" in
    "send") send_alert "$2" "$3" "$4" "$5" "$6" "$7" ;;
    "ip-ban") send_ip_ban_alert "$2" "$3" "$4" ;;
    "incident") send_security_incident_alert "$2" "$3" "$4" "$5" ;;
    "waf") send_waf_attack_alert "$2" "$3" "$4" ;;
    "health") send_system_health_alert "$2" "$3" "$4" ;;
    "test") test_all_channels ;;
    "stats") show_alert_stats ;;
    *) echo "Usage: $0 [send|ip-ban|incident|waf|health|test|stats]"
       echo "  send <severity> <title> <message> [type] [template] [vars]"
       echo "  ip-ban <ip> <reason> <duration>"
       echo "  incident <id> <severity> <type> <description>"
       echo "  waf <attack_type> <ip> <request>"
       echo "  health <component> <status> <details>"
       echo "  test - Test all notification channels"
       echo "  stats - Show alert statistics"
       ;;
esac
EOF
    
    safe_mv "/tmp/alert-manager.sh" "$alerting_dir/alert-manager.sh" "Install alert manager"
    execute_cmd "chmod +x $alerting_dir/alert-manager.sh" "Make alert manager executable"
}

setup_alerting_services() {
    local alerting_dir="$1"
    
    log_info "Setting up alerting system services"
    
    # Alert processing service
    cat > /tmp/jarvis-alert-processor.service << EOF
[Unit]
Description=jstack Alert Processing Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=/bin/bash -c 'while true; do $alerting_dir/alert-manager.sh stats >/dev/null; sleep 300; done'
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    execute_cmd "sudo mv /tmp/jarvis-alert-processor.service /etc/systemd/system/" "Install alert processor service"
    
    # Daily alert summary timer
    cat > /tmp/jarvis-alert-summary.service << EOF
[Unit]
Description=jstack Daily Alert Summary
After=network.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$alerting_dir/alert-manager.sh stats
EOF
    
    cat > /tmp/jarvis-alert-summary.timer << 'EOF'
[Unit]
Description=Generate daily jstack alert summary
Requires=jarvis-alert-summary.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    execute_cmd "sudo mv /tmp/jarvis-alert-summary.service /etc/systemd/system/" "Install summary service"
    execute_cmd "sudo mv /tmp/jarvis-alert-summary.timer /etc/systemd/system/" "Install summary timer"
    
    # Enable services
    execute_cmd "sudo systemctl daemon-reload" "Reload systemd for alerting"
    execute_cmd "sudo systemctl enable jarvis-alert-processor" "Enable alert processor"
    execute_cmd "sudo systemctl enable jarvis-alert-summary.timer" "Enable summary timer"
}

# Test all notification channels
test_notification_channels() {
    log_section "Testing All Notification Channels"
    
    local alerting_dir="$BASE_DIR/security/alerting"
    
    if [[ -f "$alerting_dir/alert-manager.sh" ]]; then
        bash "$alerting_dir/alert-manager.sh" test
    else
        log_error "Alert manager not found - run setup first"
        return 1
    fi
}

# Main function
main() {
    case "${1:-setup}" in
        "setup") setup_alerting_system ;;
        "test") test_notification_channels ;;
        "status")
            systemctl status jarvis-alert-processor 2>/dev/null || echo "Alert processor not running"
            systemctl status jarvis-alert-summary.timer 2>/dev/null || echo "Summary timer not running"
            ;;
        "start")
            sudo systemctl start jarvis-alert-processor 2>/dev/null || log_warning "Could not start alert processor"
            sudo systemctl start jarvis-alert-summary.timer 2>/dev/null || log_warning "Could not start summary timer"
            ;;
        "stop")
            sudo systemctl stop jarvis-alert-processor 2>/dev/null || log_warning "Could not stop alert processor"
            sudo systemctl stop jarvis-alert-summary.timer 2>/dev/null || log_warning "Could not stop summary timer"
            ;;
        *) echo "Usage: $0 [setup|test|status|start|stop]"
           echo "Automated security alerting system for jstack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi