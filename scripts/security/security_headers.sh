#!/bin/bash
# Security Headers and Web Application Firewall Module for JStack Stack
# Implements comprehensive OWASP security headers and basic WAF functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🛡️ COMPREHENSIVE SECURITY HEADERS
# ═══════════════════════════════════════════════════════════════════════════════

create_security_headers_config() {
    log_section "Creating Comprehensive Security Headers Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create comprehensive security headers"
        return 0
    fi
    
    start_section_timer "Security Headers"
    
    local nginx_security_dir="$BASE_DIR/security/nginx"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $nginx_security_dir" "Create NGINX security directory"
    
    # Comprehensive security headers configuration
    cat > /tmp/security-headers.conf << 'EOF'
# Comprehensive Security Headers for JStack Stack
# Based on OWASP recommendations and modern security best practices

# ═════════════════════════════════════════════════════════════════
# CORE SECURITY HEADERS
# ═════════════════════════════════════════════════════════════════

# Content Security Policy (CSP) - Primary XSS protection
add_header Content-Security-Policy "
    default-src 'self';
    script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://unpkg.com;
    style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net;
    font-src 'self' https://fonts.gstatic.com data:;
    img-src 'self' data: https: blob:;
    connect-src 'self' wss: ws:;
    frame-src 'self';
    object-src 'none';
    base-uri 'self';
    form-action 'self';
    upgrade-insecure-requests;
" always;

# X-Frame-Options - Clickjacking protection
add_header X-Frame-Options "DENY" always;

# X-Content-Type-Options - MIME type sniffing protection
add_header X-Content-Type-Options "nosniff" always;

# X-XSS-Protection - XSS filtering (legacy browsers)
add_header X-XSS-Protection "1; mode=block" always;

# Referrer-Policy - Control referrer information
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Permissions-Policy - Feature policy for modern browsers
add_header Permissions-Policy "
    accelerometer=(),
    camera=(),
    geolocation=(),
    gyroscope=(),
    magnetometer=(),
    microphone=(),
    payment=(),
    usb=()
" always;

# ═════════════════════════════════════════════════════════════════
# ADVANCED SECURITY HEADERS
# ═════════════════════════════════════════════════════════════════

# Strict-Transport-Security (HSTS) - Force HTTPS
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

# Cross-Origin-Embedder-Policy - Isolation protection
add_header Cross-Origin-Embedder-Policy "require-corp" always;

# Cross-Origin-Opener-Policy - Process isolation
add_header Cross-Origin-Opener-Policy "same-origin" always;

# Cross-Origin-Resource-Policy - Resource sharing control
add_header Cross-Origin-Resource-Policy "same-origin" always;

# ═════════════════════════════════════════════════════════════════
# APPLICATION-SPECIFIC SECURITY HEADERS
# ═════════════════════════════════════════════════════════════════

# X-Robots-Tag - Search engine control for admin areas
location ~* /(admin|administrator|wp-admin|phpmyadmin|adminer) {
    add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive" always;
    return 404; # Block access to these paths entirely
}

# Cache-Control for sensitive endpoints
location ~* /(rest/login|auth/v1|rest/oauth2) {
    add_header Cache-Control "no-store, no-cache, must-revalidate, private" always;
    add_header Pragma "no-cache" always;
    add_header Expires "0" always;
}

# ═════════════════════════════════════════════════════════════════
# CUSTOM SECURITY HEADERS FOR JARVIS STACK
# ═════════════════════════════════════════════════════════════════

# X-Content-Security-Policy (legacy IE support)
add_header X-Content-Security-Policy "default-src 'self'" always;

# X-WebKit-CSP (legacy WebKit support)
add_header X-WebKit-CSP "default-src 'self'" always;

# X-Permitted-Cross-Domain-Policies - Flash/PDF security
add_header X-Permitted-Cross-Domain-Policies "none" always;

# X-Download-Options - Prevent file execution in IE
add_header X-Download-Options "noopen" always;

# X-DNS-Prefetch-Control - DNS prefetch control
add_header X-DNS-Prefetch-Control "off" always;

# Clear server identification
more_clear_headers "Server";
more_clear_headers "X-Powered-By";
server_tokens off;

# Custom security identifier (optional)
add_header X-Security-Stack "JStack-Enhanced" always;

# ═════════════════════════════════════════════════════════════════
# CONDITIONAL HEADERS BASED ON ENVIRONMENT
# ═════════════════════════════════════════════════════════════════

# Development vs Production headers
map $deployment_env $csp_report_uri {
    default "";
    development ""; # No reporting in dev
    production "/csp-report"; # CSP violation reporting in prod
}

# Environment-specific CSP reporting
add_header Content-Security-Policy-Report-Only "default-src 'self'; report-uri $csp_report_uri" always;

# ═════════════════════════════════════════════════════════════════
# SECURITY HEADER VALIDATION MAP
# ═════════════════════════════════════════════════════════════════

# Map for header validation (used in monitoring)
map $sent_http_x_frame_options $security_headers_status {
    default "missing";
    "DENY" "ok";
    "SAMEORIGIN" "weak";
}
EOF
    
    safe_mv "/tmp/security-headers.conf" "$nginx_security_dir/security-headers.conf" "Install security headers config"
    
    # Create CSP reporting endpoint configuration
    create_csp_reporting_config "$nginx_security_dir"
    
    end_section_timer "Security Headers"
}

create_csp_reporting_config() {
    local security_dir="$1"
    
    log_info "Creating CSP violation reporting configuration"
    
    # CSP violation reporting endpoint
    cat > /tmp/csp-reporting.conf << 'EOF'
# CSP Violation Reporting Configuration

# CSP report endpoint
location /csp-report {
    # Limit to POST requests only
    limit_except POST { deny all; }
    
    # Rate limiting for CSP reports
    limit_req zone=api_strict burst=10 nodelay;
    
    # Log CSP violations
    access_log /home/jarvis/jstack/logs/nginx/csp-violations.log main;
    error_log /home/jarvis/jstack/logs/nginx/csp-errors.log;
    
    # Return success response
    return 204;
}

# Security.txt endpoint (RFC 9116)
location /.well-known/security.txt {
    add_header Content-Type "text/plain; charset=utf-8" always;
    return 200 "Contact: mailto:security@${DOMAIN}
Expires: 2025-12-31T23:59:59.000Z
Encryption: https://${DOMAIN}/.well-known/pgp-key.txt
Preferred-Languages: en
Canonical: https://${DOMAIN}/.well-known/security.txt
Policy: https://${DOMAIN}/security-policy
Acknowledgments: https://${DOMAIN}/security-acknowledgments
";
}

# Robots.txt with security considerations
location /robots.txt {
    add_header Content-Type "text/plain; charset=utf-8" always;
    return 200 "User-agent: *
Disallow: /admin/
Disallow: /api/
Disallow: /rest/login
Disallow: /auth/v1/
Disallow: /.env
Disallow: /docker-compose.yml
Disallow: /config/

# Security-focused crawling restrictions
User-agent: *
Crawl-delay: 10

Sitemap: https://${DOMAIN}/sitemap.xml
";
}
EOF
    
    safe_mv "/tmp/csp-reporting.conf" "$security_dir/csp-reporting.conf" "Install CSP reporting config"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔒 WEB APPLICATION FIREWALL (WAF) RULES
# ═══════════════════════════════════════════════════════════════════════════════

create_waf_rules() {
    log_section "Creating Web Application Firewall Rules"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create WAF rules"
        return 0
    fi
    
    start_section_timer "WAF Rules"
    
    local nginx_security_dir="$BASE_DIR/security/nginx"
    
    # Comprehensive WAF rules
    cat > /tmp/waf-rules.conf << 'EOF'
# Web Application Firewall Rules for JStack Stack
# Based on OWASP Core Rule Set patterns

# ═════════════════════════════════════════════════════════════════
# SQL INJECTION PROTECTION
# ═════════════════════════════════════════════════════════════════

# Block SQL injection patterns in query strings
location ~ "(\?|&|;|=).*(union|select|insert|delete|update|drop|create|alter|exec|execute)" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 403 "SQL injection attempt blocked";
}

# Block SQL injection in POST body (basic detection)
location ~ ".*" {
    if ($request_body ~ "(union|select|insert|delete|update|drop|create|alter|exec|execute).*(from|into|where|table|database|information_schema)") {
        access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
        return 403 "SQL injection in body blocked";
    }
}

# ═════════════════════════════════════════════════════════════════
# XSS PROTECTION
# ═════════════════════════════════════════════════════════════════

# Block XSS patterns
location ~ "(\?|&|;|=|<|>|%3C|%3E).*(script|javascript|vbscript|onload|onerror|onclick)" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 403 "XSS attempt blocked";
}

# Block HTML injection attempts
location ~ ".*" {
    if ($args ~ "(<|%3C).*(>|%3E|script|iframe|object|embed|form)") {
        access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
        return 403 "HTML injection blocked";
    }
}

# ═════════════════════════════════════════════════════════════════
# PATH TRAVERSAL PROTECTION
# ═════════════════════════════════════════════════════════════════

# Block directory traversal attempts
location ~ "(\.\./|\.\.%2F|\.\.%2f|\.\.%5C|\.\.%5c)" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 403 "Directory traversal blocked";
}

# Block null byte attacks
location ~ ".*%00.*" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 403 "Null byte attack blocked";
}

# ═════════════════════════════════════════════════════════════════
# FILE INCLUSION PROTECTION
# ═════════════════════════════════════════════════════════════════

# Block local/remote file inclusion attempts
location ~ "(include|require|include_once|require_once).*(php://|file://|http://|https://|ftp://)" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 403 "File inclusion attempt blocked";
}

# Block sensitive file access attempts
location ~ "\.(env|config|conf|ini|log|bak|backup|old|tmp|temp|swp|~)$" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 403 "Sensitive file access blocked";
}

# ═════════════════════════════════════════════════════════════════
# COMMAND INJECTION PROTECTION
# ═════════════════════════════════════════════════════════════════

# Block command injection patterns
location ~ "(\?|&|;|=).*(;|%3B|\||%7C|&|%26|\$|%24|`|%60)" {
    if ($args ~ "(whoami|id|pwd|ls|cat|wget|curl|nc|netcat|bash|sh|cmd|powershell)") {
        access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
        return 403 "Command injection blocked";
    }
}

# ═════════════════════════════════════════════════════════════════
# USER AGENT AND HEADER VALIDATION
# ═════════════════════════════════════════════════════════════════

# Block empty or suspicious user agents
location ~ ".*" {
    if ($http_user_agent = "") {
        access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
        return 403 "Empty user agent blocked";
    }
    
    if ($http_user_agent ~* "(sqlmap|nmap|masscan|nikto|havij|libwww|python|perl|ruby|curl|wget)") {
        access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
        return 403 "Scanning tool blocked";
    }
}

# Block suspicious referrers
location ~ ".*" {
    if ($http_referer ~* "(viagra|casino|poker|porn|sex|adult|pills|pharmacy)") {
        access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
        return 403 "Spam referrer blocked";
    }
}

# ═════════════════════════════════════════════════════════════════
# APPLICATION-SPECIFIC PROTECTIONS
# ═════════════════════════════════════════════════════════════════

# Protect against common CMS vulnerabilities
location ~* "(wp-admin|wp-login|wp-config|wp-content|wordpress|drupal|joomla|magento)" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 404 "CMS path not found";
}

# Block access to common admin paths
location ~* "/(admin|administrator|manager|control|panel|cpanel|plesk|phpmyadmin|adminer)" {
    access_log /home/jarvis/jstack/logs/nginx/waf-blocks.log;
    return 404 "Admin path not found";
}

# ═════════════════════════════════════════════════════════════════
# RATE LIMITING FOR SECURITY
# ═════════════════════════════════════════════════════════════════

# Aggressive rate limiting for sensitive endpoints
location ~* "/(rest/login|auth/v1|rest/oauth2)" {
    limit_req zone=auth burst=3 nodelay;
    limit_req_status 429;
}

# Rate limiting for API endpoints
location ~* "/rest/v1/" {
    limit_req zone=api_moderate burst=10 nodelay;
    limit_req_status 429;
}

# Rate limiting for webhook endpoints
location ~* "/webhook/" {
    limit_req zone=webhooks burst=20 nodelay;
    limit_req_status 429;
}

# ═════════════════════════════════════════════════════════════════
# CONTENT VALIDATION
# ═════════════════════════════════════════════════════════════════

# Block oversized requests
client_max_body_size 100M;
client_body_buffer_size 128k;
client_header_buffer_size 3m;
large_client_header_buffers 4 256k;

# Block slow HTTP attacks
client_body_timeout 30s;
client_header_timeout 30s;
send_timeout 30s;

# Validate HTTP methods
location ~ ".*" {
    limit_except GET HEAD POST PUT DELETE OPTIONS PATCH {
        deny all;
    }
}
EOF
    
    safe_mv "/tmp/waf-rules.conf" "$nginx_security_dir/waf-rules.conf" "Install WAF rules"
    
    # Create WAF monitoring script
    create_waf_monitoring_script "$nginx_security_dir"
    
    end_section_timer "WAF Rules"
}

create_waf_monitoring_script() {
    local security_dir="$1"
    
    log_info "Creating WAF monitoring and reporting script"
    
    cat > /tmp/waf-monitor.sh << 'EOF'
#!/bin/bash
# WAF Monitoring and Reporting Script for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

WAF_LOG="/home/jarvis/jstack/logs/nginx/waf-blocks.log"
ACCESS_LOG="/home/jarvis/jstack/logs/nginx/access.log"
REPORT_DIR="/home/jarvis/jstack/logs/security"

# Ensure report directory exists
mkdir -p "$REPORT_DIR"

analyze_waf_blocks() {
    log_section "Analyzing WAF Block Events"
    
    if [[ ! -f "$WAF_LOG" ]]; then
        log_warning "WAF log file not found: $WAF_LOG"
        return 1
    fi
    
    local report_file="$REPORT_DIR/waf-analysis-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "JStack Stack WAF Analysis Report"
        echo "Generated: $(date)"
        echo "========================================"
        echo ""
        
        # Top blocked IPs
        echo "=== Top 10 Blocked IPs (Last 24h) ==="
        grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$WAF_LOG" 2>/dev/null | \
            awk '{print $1}' | sort | uniq -c | sort -nr | head -10 || echo "No blocks found"
        echo ""
        
        # Attack types
        echo "=== Attack Types Distribution ==="
        local attack_patterns=(
            "SQL injection"
            "XSS attempt"
            "Directory traversal"
            "File inclusion"
            "Command injection"
            "Scanning tool"
        )
        
        for pattern in "${attack_patterns[@]}"; do
            local count=$(grep -c "$pattern" "$WAF_LOG" 2>/dev/null || echo "0")
            echo "$pattern: $count"
        done
        echo ""
        
        # Hourly distribution
        echo "=== Attacks by Hour (Last 24h) ==="
        for hour in {0..23}; do
            local hour_pattern=$(printf "%02d" "$hour")
            local count=$(grep "$(date '+%d/%b/%Y').*:$hour_pattern:" "$WAF_LOG" 2>/dev/null | wc -l)
            echo "Hour $hour_pattern: $count attacks"
        done | sort -k3 -nr | head -5
        echo ""
        
        # Geographic analysis (if GeoIP available)
        echo "=== Recent Attack Details ==="
        tail -20 "$WAF_LOG" 2>/dev/null || echo "No recent attacks"
        
    } > "$report_file"
    
    log_success "WAF analysis report generated: $report_file"
}

monitor_attack_trends() {
    log_info "Monitoring attack trends and patterns"
    
    # Check for attack spikes
    local current_hour_blocks=$(grep "$(date '+%d/%b/%Y.*:%H:')" "$WAF_LOG" 2>/dev/null | wc -l)
    local previous_hour_blocks=$(grep "$(date -d '1 hour ago' '+%d/%b/%Y.*:%H:')" "$WAF_LOG" 2>/dev/null | wc -l)
    
    if [[ $current_hour_blocks -gt $((previous_hour_blocks * 2)) ]] && [[ $current_hour_blocks -gt 10 ]]; then
        log_warning "Attack spike detected: $current_hour_blocks blocks this hour (vs $previous_hour_blocks last hour)"
        
        # Auto-block aggressive IPs
        grep "$(date '+%d/%b/%Y.*:%H:')" "$WAF_LOG" | \
            awk '{print $1}' | sort | uniq -c | sort -nr | head -5 | \
            while read count ip; do
                if [[ $count -gt 5 ]]; then
                    log_warning "IP $ip blocked $count times this hour - adding to fail2ban"
                    # Add to fail2ban (requires fail2ban-client)
                    fail2ban-client set nginx-badbots banip "$ip" 2>/dev/null || true
                fi
            done
    fi
}

generate_security_dashboard() {
    log_info "Generating security dashboard data"
    
    local dashboard_file="$REPORT_DIR/security-dashboard.json"
    
    # Generate JSON data for dashboard
    cat > "$dashboard_file" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "waf_stats": {
        "total_blocks_24h": $(grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$WAF_LOG" 2>/dev/null | wc -l),
        "blocks_last_hour": $(grep "$(date '+%d/%b/%Y.*:%H:')" "$WAF_LOG" 2>/dev/null | wc -l),
        "unique_attackers_24h": $(grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$WAF_LOG" 2>/dev/null | awk '{print $1}' | sort -u | wc -l),
        "top_attack_type": "$(grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$WAF_LOG" 2>/dev/null | grep -o 'blocked' | head -1 || echo 'none')"
    },
    "fail2ban_stats": {
        "active_bans": $(fail2ban-client status 2>/dev/null | grep -o "Currently banned:.*" | grep -o "[0-9]*" || echo "0"),
        "total_bans_24h": $(grep "$(date '+%Y-%m-%d')" /var/log/fail2ban.log 2>/dev/null | grep -c "Ban" || echo "0")
    },
    "nginx_stats": {
        "total_requests_24h": $(grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$ACCESS_LOG" 2>/dev/null | wc -l),
        "4xx_errors_24h": $(grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$ACCESS_LOG" 2>/dev/null | grep -c " 4[0-9][0-9] " || echo "0"),
        "5xx_errors_24h": $(grep "$(date -d '1 day ago' '+%d/%b/%Y')" "$ACCESS_LOG" 2>/dev/null | grep -c " 5[0-9][0-9] " || echo "0")
    }
}
EOF
    
    log_success "Security dashboard data generated: $dashboard_file"
}

case "${1:-analyze}" in
    "analyze") analyze_waf_blocks ;;
    "monitor") monitor_attack_trends ;;
    "dashboard") generate_security_dashboard ;;
    "all") 
        analyze_waf_blocks
        monitor_attack_trends
        generate_security_dashboard
        ;;
    *) echo "Usage: $0 [analyze|monitor|dashboard|all]"
       echo "WAF monitoring and analysis for JStack Stack" ;;
esac
EOF
    
    safe_mv "/tmp/waf-monitor.sh" "$security_dir/waf-monitor.sh" "Install WAF monitoring script"
    execute_cmd "chmod +x $security_dir/waf-monitor.sh" "Make WAF monitor executable"
}

# Main function
main() {
    case "${1:-setup}" in
        "headers") create_security_headers_config ;;
        "waf") create_waf_rules ;;
        "setup"|"all")
            create_security_headers_config
            create_waf_rules
            ;;
        *) echo "Usage: $0 [setup|headers|waf|all]"
           echo "Security headers and WAF for JStack Stack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi