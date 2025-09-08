#!/bin/bash
# Network Security Enhancement Module for JStack Stack
# Implements fail2ban, advanced rate limiting, geographic filtering, and threat response

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🚫 FAIL2BAN WEB APPLICATION PROTECTION
# ═══════════════════════════════════════════════════════════════════════════════

setup_fail2ban() {
    log_section "Setting up fail2ban Web Application Protection"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup fail2ban web application protection"
        return 0
    fi
    
    start_section_timer "fail2ban Setup"
    
    # Install fail2ban if not present
    if ! command -v fail2ban-server >/dev/null 2>&1; then
        log_info "Installing fail2ban"
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            case "$ID" in
                "arch")
                    execute_cmd "sudo pacman -S --noconfirm fail2ban" "Install fail2ban (Arch)"
                    ;;
                "ubuntu"|"debian")
                    execute_cmd "sudo apt-get update && sudo apt-get install -y fail2ban" "Install fail2ban (Debian/Ubuntu)"
                    ;;
                *)
                    log_error "Unsupported OS for fail2ban installation: $ID"
                    return 1
                    ;;
            esac
        fi
    else
        log_info "fail2ban already installed"
    fi
    
    # Create fail2ban configuration directory
    local fail2ban_dir="/etc/fail2ban"
    execute_cmd "sudo mkdir -p $fail2ban_dir/jail.d" "Create fail2ban jail.d directory"
    execute_cmd "sudo mkdir -p $fail2ban_dir/filter.d" "Create fail2ban filter.d directory"
    execute_cmd "sudo mkdir -p $fail2ban_dir/action.d" "Create fail2ban action.d directory"
    
    # Create JStack-specific fail2ban configuration
    create_jarvis_fail2ban_config
    
    # Enable and start fail2ban service
    execute_cmd "sudo systemctl enable fail2ban" "Enable fail2ban service"
    execute_cmd "sudo systemctl restart fail2ban" "Restart fail2ban service"
    
    end_section_timer "fail2ban Setup"
    log_success "fail2ban web application protection configured"
}

create_jarvis_fail2ban_config() {
    log_info "Creating JStack-specific fail2ban configuration"
    
    # Main jail configuration for JStack Stack
    cat > /tmp/jstack.local << 'EOF'
# JStack Stack fail2ban Configuration
# Protects N8N, Supabase, and NGINX from web-based attacks

[DEFAULT]
# Global settings
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

# Email notifications (if configured)
destemail = ${ALERT_EMAIL:-admin@${DOMAIN}}
sendername = JStack-fail2ban
mta = sendmail

# Actions
action = %(action_mwl)s

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /home/jarvis/jstack/logs/nginx/access.log
maxretry = 3
bantime = 1800

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /home/jarvis/jstack/logs/nginx/access.log
maxretry = 6
bantime = 3600

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /home/jarvis/jstack/logs/nginx/access.log
maxretry = 2
bantime = 86400

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /home/jarvis/jstack/logs/nginx/access.log
maxretry = 2
bantime = 86400

[n8n-auth]
enabled = true
port = http,https
filter = n8n-auth
logpath = /home/jarvis/jstack/logs/nginx/access.log
maxretry = 5
findtime = 300
bantime = 1800

[supabase-api-abuse]
enabled = true
port = http,https
filter = supabase-api-abuse
logpath = /home/jarvis/jstack/logs/nginx/access.log
maxretry = 20
findtime = 60
bantime = 600

[nginx-req-limit]
enabled = true
port = http,https
filter = nginx-req-limit
logpath = /home/jarvis/jstack/logs/nginx/error.log
maxretry = 10
findtime = 600
bantime = 3600

# SSH protection (enhanced from default)
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    execute_cmd "sudo mv /tmp/jstack.local /etc/fail2ban/jail.d/jstack.local" "Install JStack jail config"
    
    # Create custom filters for JStack applications
    create_custom_fail2ban_filters
}

create_custom_fail2ban_filters() {
    log_info "Creating custom fail2ban filters for JStack applications"
    
    # N8N authentication failures
    cat > /tmp/n8n-auth.conf << 'EOF'
# fail2ban filter for N8N authentication failures
[Definition]
failregex = ^<HOST> - .* "POST /rest/login HTTP.*" 401
            ^<HOST> - .* "POST /rest/oauth2/callback HTTP.*" 401
            ^<HOST> - .* "GET /rest/login HTTP.*" 403

ignoreregex = 
EOF
    
    execute_cmd "sudo mv /tmp/n8n-auth.conf /etc/fail2ban/filter.d/n8n-auth.conf" "Install N8N auth filter"
    
    # Supabase API abuse detection
    cat > /tmp/supabase-api-abuse.conf << 'EOF'
# fail2ban filter for Supabase API abuse
[Definition]
failregex = ^<HOST> - .* "POST /auth/v1/.* HTTP.*" 429
            ^<HOST> - .* "GET /rest/v1/.* HTTP.*" 429
            ^<HOST> - .* ".* /auth/v1/.* HTTP.*" 401
            ^<HOST> - .* ".* /rest/v1/.* HTTP.*" 403
            ^<HOST> - .* ".* /rest/v1/.* HTTP.*" 400

ignoreregex =
EOF
    
    execute_cmd "sudo mv /tmp/supabase-api-abuse.conf /etc/fail2ban/filter.d/supabase-api-abuse.conf" "Install Supabase API abuse filter"
    
    # NGINX request limit violations
    cat > /tmp/nginx-req-limit.conf << 'EOF'
# fail2ban filter for NGINX rate limiting
[Definition]
failregex = limiting requests, excess: .* by zone .*, client: <HOST>
            client <HOST> exceeded limit

ignoreregex =
EOF
    
    execute_cmd "sudo mv /tmp/nginx-req-limit.conf /etc/fail2ban/filter.d/nginx-req-limit.conf" "Install NGINX req limit filter"
    
    # Bad bots and scanners
    cat > /tmp/nginx-badbots.conf << 'EOF'
# fail2ban filter for bad bots and scanners
[Definition]
failregex = ^<HOST> -.*GET.*(\.php|\.asp|\.exe|\.pl|\.cgi|\.scgi)
            ^<HOST> -.*GET.*(/admin|/administrator|/wp-admin|/wp-login|/phpmyadmin)
            ^<HOST> -.*"(GET|POST).*HTTP.*" 404.*
            ^<HOST> -.*".*sqlmap.*".*
            ^<HOST> -.*".*nikto.*".*
            ^<HOST> -.*".*nmap.*".*

ignoreregex =
EOF
    
    execute_cmd "sudo mv /tmp/nginx-badbots.conf /etc/fail2ban/filter.d/nginx-badbots.conf" "Install bad bots filter"
    
    # Custom action for JStack notifications
    cat > /tmp/jarvis-notification.conf << EOF
# Custom notification action for JStack Stack
[Definition]
actionstart = echo "fail2ban service started on \$(hostname) at \$(date)" | logger -t jarvis-fail2ban
actionstop = echo "fail2ban service stopped on \$(hostname) at \$(date)" | logger -t jarvis-fail2ban
actioncheck = 
actionban = echo "Banned <ip> for <failures> failures in jail <name> at \$(date)" | logger -t jarvis-fail2ban
            iptables -I INPUT -s <ip> -j DROP
actionunban = echo "Unbanned <ip> from jail <name> at \$(date)" | logger -t jarvis-fail2ban
              iptables -D INPUT -s <ip> -j DROP

[Init]
init = 123
EOF
    
    execute_cmd "sudo mv /tmp/jarvis-notification.conf /etc/fail2ban/action.d/jarvis-notification.conf" "Install custom notification action"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 ADVANCED NGINX RATE LIMITING
# ═══════════════════════════════════════════════════════════════════════════════

create_advanced_rate_limiting() {
    log_section "Creating Advanced NGINX Rate Limiting Configuration"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create advanced NGINX rate limiting"
        return 0
    fi
    
    start_section_timer "Rate Limiting"
    
    local nginx_security_dir="$BASE_DIR/security/nginx"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $nginx_security_dir" "Create NGINX security directory"
    
    # Advanced rate limiting configuration
    cat > /tmp/rate-limiting.conf << 'EOF'
# Advanced Rate Limiting for JStack Stack
# Multiple zones with different limits for different endpoints

# Define rate limiting zones
limit_req_zone $binary_remote_addr zone=api_strict:10m rate=5r/s;
limit_req_zone $binary_remote_addr zone=api_moderate:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api_lenient:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=2r/s;
limit_req_zone $binary_remote_addr zone=webhooks:10m rate=100r/s;
limit_req_zone $binary_remote_addr zone=static:10m rate=50r/s;
limit_req_zone $binary_remote_addr zone=uploads:10m rate=3r/s;

# Connection limiting
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
limit_conn_zone $server_name zone=conn_limit_per_server:10m;

# Request body size limits
client_max_body_size 100M;
client_body_buffer_size 128k;
client_header_buffer_size 3m;
large_client_header_buffers 4 256k;

# Timeouts for security
client_body_timeout 30s;
client_header_timeout 30s;
send_timeout 30s;
keepalive_timeout 65s;

# Security configurations
server_tokens off;  # Hide NGINX version
more_clear_headers Server;  # Remove server header completely (requires nginx-extras)

# Geographic blocking (placeholder - requires GeoIP module)
# map $geoip_country_code $allowed_country {
#     default yes;
#     CN no;  # Block China
#     RU no;  # Block Russia
#     KP no;  # Block North Korea
# }

# Rate limiting maps
map $request_uri $rate_limit_zone {
    default                     "api_lenient";
    ~*/rest/login               "auth";
    ~*/auth/v1/.*               "auth";
    ~*/rest/oauth2/.*           "auth";
    ~*/rest/v1/.*               "api_moderate";
    ~*/webhook/.*               "webhooks";
    ~*/static/.*                "static";
    ~*/uploads/.*               "uploads";
    ~*/admin/.*                 "api_strict";
}

# Bad bot detection
map $http_user_agent $bad_bot {
    default 0;
    ~*bot 1;
    ~*crawler 1;
    ~*spider 1;
    ~*scanner 1;
    ~*nikto 1;
    ~*sqlmap 1;
    ~*nmap 1;
    ~*masscan 1;
    "" 1;  # Empty user agent
}

# Suspicious request patterns
map $request_uri $suspicious_request {
    default 0;
    ~*\.(php|asp|exe|pl|cgi|scgi)$ 1;
    ~*/(admin|administrator|wp-admin|wp-login|phpmyadmin) 1;
    ~*\.\./\.\. 1;
    ~*select.*from.*information_schema 1;
    ~*union.*select 1;
    ~*<script 1;
    ~*javascript: 1;
}

# Rate limiting logic
limit_req_status 429;
limit_conn_status 429;

# Custom error pages for rate limiting
error_page 429 /429.html;
EOF
    
    safe_mv "/tmp/rate-limiting.conf" "$nginx_security_dir/rate-limiting.conf" "Install rate limiting config"
    
    # Create custom error pages
    create_custom_error_pages "$nginx_security_dir"
    
    end_section_timer "Rate Limiting"
}

create_custom_error_pages() {
    local security_dir="$1"
    
    log_info "Creating custom error pages for security responses"
    
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $security_dir/error-pages" "Create error pages directory"
    
    # 429 Too Many Requests page
    cat > /tmp/429.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Rate Limit Exceeded - JStack Stack</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #e74c3c; margin-bottom: 20px; }
        p { color: #666; line-height: 1.6; margin-bottom: 15px; }
        .code { color: #2c3e50; font-size: 24px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="code">429</div>
        <h1>Rate Limit Exceeded</h1>
        <p>You have exceeded the allowed number of requests per minute.</p>
        <p>Please wait a moment before trying again.</p>
        <p>If you believe this is an error, please contact the administrator.</p>
    </div>
</body>
</html>
EOF
    
    safe_mv "/tmp/429.html" "$security_dir/error-pages/429.html" "Install 429 error page"
    
    # 403 Forbidden page (for blocked regions/bots)
    cat > /tmp/403.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Access Forbidden - JStack Stack</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #e74c3c; margin-bottom: 20px; }
        p { color: #666; line-height: 1.6; margin-bottom: 15px; }
        .code { color: #2c3e50; font-size: 24px; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="code">403</div>
        <h1>Access Forbidden</h1>
        <p>Your request has been blocked by our security system.</p>
        <p>This may be due to suspicious activity or geographic restrictions.</p>
        <p>If you believe this is an error, please contact the administrator.</p>
    </div>
</body>
</html>
EOF
    
    safe_mv "/tmp/403.html" "$security_dir/error-pages/403.html" "Install 403 error page"
    
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$security_dir/error-pages/" "Set error pages ownership"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌍 GEOGRAPHIC IP FILTERING AND WAF RULES
# ═══════════════════════════════════════════════════════════════════════════════

setup_geographic_filtering() {
    log_section "Setting up Geographic IP Filtering"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup geographic IP filtering"
        return 0
    fi
    
    start_section_timer "Geographic Filtering"
    
    local security_dir="$BASE_DIR/security/nginx"
    
    # Create IP blacklist management script
    cat > /tmp/ip-blacklist-manager.sh << 'EOF'
#!/bin/bash
# IP Blacklist Management for JStack Stack

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

BLACKLIST_FILE="/home/jarvis/jstack/security/nginx/blocked-ips.conf"
WHITELIST_FILE="/home/jarvis/jstack/security/nginx/allowed-ips.conf"
TEMP_BLACKLIST="/tmp/blocked-ips-temp.conf"

# Initialize blacklist files
init_blacklists() {
    log_info "Initializing IP blacklist files"
    
    mkdir -p "$(dirname "$BLACKLIST_FILE")"
    mkdir -p "$(dirname "$WHITELIST_FILE")"
    
    # Create initial whitelist (RFC 1918 private networks)
    cat > "$WHITELIST_FILE" << 'WHITELIST_EOF'
# JStack Stack - Whitelisted IP ranges
# Private network ranges (always allowed)
allow 127.0.0.0/8;      # Loopback
allow 10.0.0.0/8;       # Private Class A
allow 172.16.0.0/12;    # Private Class B
allow 192.168.0.0/16;   # Private Class C

# Add your trusted IP ranges here
# allow 203.0.113.0/24;  # Example: Office network
# allow 198.51.100.0/24; # Example: VPN network
WHITELIST_EOF
    
    # Create initial blacklist with known bad actors
    cat > "$BLACKLIST_FILE" << 'BLACKLIST_EOF'
# JStack Stack - Blocked IP ranges
# Known malicious networks and attackers

# Tor exit nodes (uncomment if you want to block Tor)
# deny 103.251.167.10;
# deny 104.244.72.115;

# Known bad actors (examples - update with real threat intelligence)
# deny 1.2.3.4;         # Example malicious IP
# deny 5.6.7.0/24;      # Example malicious network

# Block entire countries (requires GeoIP - examples)
# China: 1.0.0.0/8, 14.0.0.0/8, 27.0.0.0/8, etc.
# Russia: 5.0.0.0/8, 31.0.0.0/8, 37.0.0.0/8, etc.
# North Korea: 175.45.176.0/22, 210.52.109.0/24, etc.

# Placeholder for dynamic entries (updated by fail2ban and monitoring)
include /home/jarvis/jstack/security/nginx/dynamic-blocks.conf;
BLACKLIST_EOF
    
    # Create dynamic blocks file
    touch "${BLACKLIST_FILE%/*}/dynamic-blocks.conf"
    
    log_success "IP blacklist files initialized"
}

# Add IP to blacklist
add_to_blacklist() {
    local ip="$1"
    local reason="${2:-Manual addition}"
    local duration="${3:-3600}"  # Default 1 hour
    
    if [[ -z "$ip" ]]; then
        log_error "IP address required"
        return 1
    fi
    
    # Validate IP format
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP format: $ip"
        return 1
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local expiry=$(date -d "+${duration} seconds" '+%s')
    
    echo "deny $ip; # Added: $timestamp | Reason: $reason | Expires: $(date -d "@$expiry")" >> "${BLACKLIST_FILE%/*}/dynamic-blocks.conf"
    
    # Reload NGINX configuration
    if command -v nginx >/dev/null 2>&1; then
        nginx -t && nginx -s reload
        log_success "Added $ip to blacklist (expires in ${duration}s)"
    else
        log_warning "NGINX not found - IP added to blacklist but not reloaded"
    fi
}

# Remove IP from blacklist
remove_from_blacklist() {
    local ip="$1"
    
    if [[ -z "$ip" ]]; then
        log_error "IP address required"
        return 1
    fi
    
    # Remove from dynamic blocks
    sed -i "/deny $ip;/d" "${BLACKLIST_FILE%/*}/dynamic-blocks.conf"
    
    # Reload NGINX configuration
    if command -v nginx >/dev/null 2>&1; then
        nginx -t && nginx -s reload
        log_success "Removed $ip from blacklist"
    else
        log_warning "NGINX not found - IP removed from blacklist but not reloaded"
    fi
}

# Clean expired entries
clean_expired() {
    log_info "Cleaning expired blacklist entries"
    
    local current_time=$(date '+%s')
    local dynamic_file="${BLACKLIST_FILE%/*}/dynamic-blocks.conf"
    local temp_file="/tmp/dynamic-blocks-clean.conf"
    
    if [[ -f "$dynamic_file" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ Expires:\ (.+)$ ]]; then
                local expire_date="${BASH_REMATCH[1]}"
                local expire_timestamp=$(date -d "$expire_date" '+%s' 2>/dev/null || echo "0")
                
                if [[ $expire_timestamp -gt $current_time ]]; then
                    echo "$line" >> "$temp_file"
                fi
            elif [[ ! "$line" =~ deny.*Expires: ]]; then
                # Keep non-expiring entries
                echo "$line" >> "$temp_file"
            fi
        done < "$dynamic_file"
        
        mv "$temp_file" "$dynamic_file"
        
        # Reload NGINX
        if command -v nginx >/dev/null 2>&1; then
            nginx -t && nginx -s reload
        fi
        
        log_success "Expired blacklist entries cleaned"
    fi
}

# Display current blacklist status
show_status() {
    log_info "Current IP blacklist status"
    
    echo "=== Whitelisted IPs ==="
    if [[ -f "$WHITELIST_FILE" ]]; then
        grep -E "^allow" "$WHITELIST_FILE" | head -20
    else
        echo "Whitelist file not found"
    fi
    
    echo -e "\n=== Blacklisted IPs ==="
    if [[ -f "$BLACKLIST_FILE" ]]; then
        grep -E "^deny" "$BLACKLIST_FILE" | head -20
    else
        echo "Blacklist file not found"
    fi
    
    echo -e "\n=== Dynamic Blocks ==="
    local dynamic_file="${BLACKLIST_FILE%/*}/dynamic-blocks.conf"
    if [[ -f "$dynamic_file" ]]; then
        local count=$(grep -c "deny" "$dynamic_file" 2>/dev/null || echo "0")
        echo "Active dynamic blocks: $count"
        if [[ $count -gt 0 ]]; then
            echo "Recent blocks:"
            tail -10 "$dynamic_file"
        fi
    else
        echo "No dynamic blocks file found"
    fi
}

case "${1:-status}" in
    "init") init_blacklists ;;
    "add") add_to_blacklist "$2" "$3" "$4" ;;
    "remove") remove_from_blacklist "$2" ;;
    "clean") clean_expired ;;
    "status") show_status ;;
    *) echo "Usage: $0 [init|add|remove|clean|status]"
       echo "  init                    - Initialize blacklist files"
       echo "  add <ip> <reason> <ttl> - Add IP to blacklist"
       echo "  remove <ip>             - Remove IP from blacklist"
       echo "  clean                   - Clean expired entries"
       echo "  status                  - Show blacklist status"
       ;;
esac
EOF
    
    safe_mv "/tmp/ip-blacklist-manager.sh" "$security_dir/ip-blacklist-manager.sh" "Install IP blacklist manager"
    execute_cmd "chmod +x $security_dir/ip-blacklist-manager.sh" "Make IP manager executable"
    
    # Initialize blacklists
    bash "$security_dir/ip-blacklist-manager.sh" init
    
    end_section_timer "Geographic Filtering"
}

# Main function
main() {
    case "${1:-setup}" in
        "fail2ban") setup_fail2ban ;;
        "rate-limit") create_advanced_rate_limiting ;;
        "geo-filter") setup_geographic_filtering ;;
        "setup"|"all")
            setup_fail2ban
            create_advanced_rate_limiting
            setup_geographic_filtering
            ;;
        "status")
            systemctl status fail2ban 2>/dev/null || echo "fail2ban not running"
            ;;
        *) echo "Usage: $0 [setup|fail2ban|rate-limit|geo-filter|status|all]"
           echo "Network security enhancement for JStack Stack" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi