#!/bin/bash
# SSL Certificate Management for COMPASS Stack
# Handles Let's Encrypt certificates, domain validation, and NGINX SSL configuration

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔐 SSL CERTIFICATE VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

# Validate domain resolution before certificate acquisition
validate_domain_resolution() {
    log_section "Validating Domain Resolution"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate domain resolution for ${DOMAIN}"
        return 0
    fi
    
    start_section_timer "Domain Validation"
    
    local domains_to_check=("${DOMAIN}" "${SUPABASE_SUBDOMAIN}.${DOMAIN}" "${STUDIO_SUBDOMAIN}.${DOMAIN}" "${N8N_SUBDOMAIN}.${DOMAIN}")
    local validation_failed=false
    
    for domain in "${domains_to_check[@]}"; do
        log_info "Validating DNS resolution for $domain"
        
        # Check if domain resolves to this server's IP
        local resolved_ip
        resolved_ip=$(dig +short "$domain" A | tail -n1)
        
        if [[ -z "$resolved_ip" ]]; then
            log_error "Domain $domain does not resolve to any IP address"
            validation_failed=true
            continue
        fi
        
        # Get server's public IP
        local server_ip
        server_ip=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s icanhazip.com)
        
        if [[ -z "$server_ip" ]]; then
            log_warning "Could not determine server's public IP - skipping IP validation for $domain"
        elif [[ "$resolved_ip" != "$server_ip" ]]; then
            log_warning "Domain $domain resolves to $resolved_ip but server IP is $server_ip"
            log_warning "SSL certificate acquisition may fail if domains don't point to this server"
        else
            log_success "Domain $domain correctly resolves to server IP $server_ip"
        fi
    done
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Domain validation failed - please ensure DNS is configured correctly"
        end_section_timer "Domain Validation"
        return 1
    fi
    
    end_section_timer "Domain Validation"
    log_success "Domain validation completed successfully"
    return 0
}

# Check if SSL certificates already exist and are valid
check_existing_certificates() {
    local cert_dir="/home/${SERVICE_USER}/jarvis-stack/services/nginx/ssl"
    
    if [[ -f "$cert_dir/live/${DOMAIN}/fullchain.pem" ]] && [[ -f "$cert_dir/live/${DOMAIN}/privkey.pem" ]]; then
        # Check certificate validity
        local cert_expiry
        cert_expiry=$(openssl x509 -in "$cert_dir/live/${DOMAIN}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [[ -n "$cert_expiry" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null)
            local current_epoch
            current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -gt 7 ]]; then
                log_info "Valid SSL certificates found (expires in $days_until_expiry days)"
                return 0
            else
                log_warning "SSL certificates expire in $days_until_expiry days - renewal needed"
                return 1
            fi
        fi
    fi
    
    log_info "No valid SSL certificates found"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 TEMPORARY CERTIFICATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Create temporary self-signed certificates for initial NGINX startup
create_temporary_certificates() {
    log_section "Creating Temporary Self-Signed Certificates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create temporary self-signed certificates"
        return 0
    fi
    
    start_section_timer "Temporary Certificates"
    
    local ssl_dir="$BASE_DIR/services/nginx/ssl"
    local temp_cert_dir="$ssl_dir/temp"
    
    # Create SSL directories
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $temp_cert_dir" "Create temporary SSL directory"
    
    # Generate temporary certificate for all domains
    local domains_san=""
    for domain in "${DOMAIN}" "${SUPABASE_SUBDOMAIN}.${DOMAIN}" "${STUDIO_SUBDOMAIN}.${DOMAIN}" "${N8N_SUBDOMAIN}.${DOMAIN}"; do
        if [[ -n "$domains_san" ]]; then
            domains_san="${domains_san},DNS:${domain}"
        else
            domains_san="DNS:${domain}"
        fi
    done
    
    # Create certificate configuration
    cat > /tmp/temp_cert.conf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=${COUNTRY_CODE}
ST=${STATE_NAME}
L=${CITY_NAME}
O=${ORGANIZATION}
CN=${DOMAIN}

[v3_req]
subjectAltName = ${domains_san}
EOF
    
    # Generate private key and certificate
    execute_cmd "openssl req -x509 -newkey rsa:2048 -keyout /tmp/temp_privkey.pem -out /tmp/temp_fullchain.pem -days 1 -nodes -config /tmp/temp_cert.conf -extensions v3_req" "Generate temporary certificate"
    
    # Install temporary certificates
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $temp_cert_dir/live/${DOMAIN}" "Create certificate directory structure"
    safe_mv "/tmp/temp_fullchain.pem" "$temp_cert_dir/live/${DOMAIN}/fullchain.pem" "Install temporary certificate"
    safe_mv "/tmp/temp_privkey.pem" "$temp_cert_dir/live/${DOMAIN}/privkey.pem" "Install temporary private key"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$temp_cert_dir/live/${DOMAIN}/" "Set certificate ownership"
    safe_chmod "600" "$temp_cert_dir/live/${DOMAIN}/privkey.pem" "Secure private key permissions"
    safe_chmod "644" "$temp_cert_dir/live/${DOMAIN}/fullchain.pem" "Set certificate permissions"
    
    # Clean up temporary files
    rm -f /tmp/temp_cert.conf
    
    end_section_timer "Temporary Certificates"
    log_success "Temporary self-signed certificates created successfully"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌍 LET'S ENCRYPT CERTIFICATE ACQUISITION
# ═══════════════════════════════════════════════════════════════════════════════

# Setup Let's Encrypt certificates
setup_letsencrypt_certificates() {
    log_section "Setting up Let's Encrypt Certificates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Let's Encrypt certificates for ${DOMAIN} and subdomains"
        return 0
    fi
    
    start_section_timer "Let's Encrypt Setup"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    
    # Ensure certbot volumes and directories exist
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $nginx_dir/certbot/{conf,www}" "Create certbot directories"
    
    # Check if NGINX container is running and stop it temporarily
    local nginx_was_running=false
    if docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
        log_info "Stopping NGINX temporarily for certificate acquisition"
        docker_cmd "cd $nginx_dir && docker-compose stop nginx-proxy" "Stop NGINX for certificate"
        nginx_was_running=true
    fi
    
    # Create temporary NGINX configuration for ACME challenge
    create_acme_challenge_server
    
    # Acquire certificates for all domains
    local domains_list="${DOMAIN} ${SUPABASE_SUBDOMAIN}.${DOMAIN} ${STUDIO_SUBDOMAIN}.${DOMAIN} ${N8N_SUBDOMAIN}.${DOMAIN}"
    local certbot_domains=""
    
    for domain in $domains_list; do
        certbot_domains="$certbot_domains -d $domain"
    done
    
    log_info "Requesting SSL certificates for: $domains_list"
    
    # Run certbot to acquire certificates
    local certbot_cmd="certbot certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email $certbot_domains"
    
    if docker_cmd "docker run --rm -v $nginx_dir/certbot/conf:/etc/letsencrypt -v $nginx_dir/certbot/www:/var/www/certbot -v $nginx_dir/logs:/var/log/certbot certbot/certbot:v2.7.4 $certbot_cmd" "Acquire SSL certificates"; then
        log_success "SSL certificates acquired successfully"
        
        # Copy certificates to NGINX SSL directory
        copy_certificates_to_nginx
        
        # Stop temporary ACME server
        stop_acme_challenge_server
        
        # Restart NGINX with proper SSL configuration if it was running
        if [[ "$nginx_was_running" == "true" ]]; then
            log_info "Restarting NGINX with SSL certificates"
            docker_cmd "cd $nginx_dir && docker-compose up -d nginx-proxy" "Restart NGINX with SSL"
            
            # Wait for NGINX to be healthy
            wait_for_service_health "nginx-proxy" 60 5
        fi
        
    else
        log_error "SSL certificate acquisition failed"
        
        # Stop temporary server
        stop_acme_challenge_server
        
        # Restart NGINX with temporary certificates if it was running
        if [[ "$nginx_was_running" == "true" ]]; then
            log_warning "Restarting NGINX with temporary certificates"
            docker_cmd "cd $nginx_dir && docker-compose up -d nginx-proxy" "Restart NGINX with temporary certs"
        fi
        
        end_section_timer "Let's Encrypt Setup"
        return 1
    fi
    
    end_section_timer "Let's Encrypt Setup"
    log_success "Let's Encrypt certificates setup completed successfully"
    return 0
}

# Create temporary NGINX server for ACME challenge
create_acme_challenge_server() {
    log_info "Creating temporary NGINX server for ACME challenge"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    
    # Create temporary NGINX configuration for ACME challenge only
    cat > /tmp/acme-nginx.conf << EOF
events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name ${DOMAIN} ${SUPABASE_SUBDOMAIN}.${DOMAIN} ${STUDIO_SUBDOMAIN}.${DOMAIN} ${N8N_SUBDOMAIN}.${DOMAIN};
        
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
            try_files \$uri \$uri/ =404;
        }
        
        location / {
            return 200 'ACME Challenge Server - Certificate Acquisition in Progress';
            add_header Content-Type text/plain;
        }
    }
}
EOF
    
    # Copy temporary configuration
    safe_mv "/tmp/acme-nginx.conf" "$nginx_dir/acme-nginx.conf" "Install ACME NGINX config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$nginx_dir/acme-nginx.conf" "Set ACME config ownership"
    
    # Start temporary NGINX container for ACME challenge
    docker_cmd "docker run -d --name nginx-acme --rm -p 80:80 -v $nginx_dir/acme-nginx.conf:/etc/nginx/nginx.conf:ro -v $nginx_dir/certbot/www:/var/www/certbot nginx:1.25-alpine" "Start ACME challenge server"
    
    # Wait for server to start
    sleep 5
    log_success "ACME challenge server started"
}

# Stop temporary ACME challenge server
stop_acme_challenge_server() {
    log_info "Stopping temporary ACME challenge server"
    docker_cmd "docker stop nginx-acme" "Stop ACME challenge server" || true
    rm -f "$BASE_DIR/services/nginx/acme-nginx.conf"
    log_success "ACME challenge server stopped"
}

# Copy certificates from certbot to NGINX SSL directory
copy_certificates_to_nginx() {
    log_info "Copying certificates to NGINX SSL directory"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    local ssl_dir="$nginx_dir/ssl"
    
    # Create SSL directory structure
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $ssl_dir/live/${DOMAIN}" "Create SSL directory structure"
    
    # Copy certificates from certbot volume
    if docker_cmd "docker run --rm -v $nginx_dir/certbot/conf:/etc/letsencrypt -v $ssl_dir:/ssl alpine:latest cp -r /etc/letsencrypt/live/${DOMAIN}/ /ssl/live/" "Copy certificates to SSL directory"; then
        # Set proper ownership and permissions
        safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$ssl_dir/" "Set SSL directory ownership"
        safe_chmod "600" "$ssl_dir/live/${DOMAIN}/privkey.pem" "Secure private key"
        safe_chmod "644" "$ssl_dir/live/${DOMAIN}/fullchain.pem" "Set certificate permissions"
        
        log_success "Certificates copied to NGINX SSL directory"
        return 0
    else
        log_error "Failed to copy certificates to NGINX SSL directory"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 NGINX SSL CONFIGURATION UPDATE
# ═══════════════════════════════════════════════════════════════════════════════

# Update NGINX configurations to use proper SSL certificate paths
update_nginx_ssl_config() {
    log_section "Updating NGINX SSL Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update NGINX SSL configurations"
        return 0
    fi
    
    start_section_timer "NGINX SSL Config Update"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    local ssl_cert_path
    local ssl_key_path
    
    # Determine certificate paths based on what's available
    if [[ -f "$nginx_dir/ssl/live/${DOMAIN}/fullchain.pem" ]]; then
        ssl_cert_path="/etc/nginx/ssl/live/${DOMAIN}/fullchain.pem"
        ssl_key_path="/etc/nginx/ssl/live/${DOMAIN}/privkey.pem"
        log_info "Using Let's Encrypt certificates"
    elif [[ -f "$nginx_dir/ssl/temp/live/${DOMAIN}/fullchain.pem" ]]; then
        ssl_cert_path="/etc/nginx/ssl/temp/live/${DOMAIN}/fullchain.pem"
        ssl_key_path="/etc/nginx/ssl/temp/live/${DOMAIN}/privkey.pem"
        log_warning "Using temporary self-signed certificates"
    else
        log_error "No SSL certificates found for NGINX configuration"
        end_section_timer "NGINX SSL Config Update"
        return 1
    fi
    
    # Update all NGINX configuration files with correct certificate paths
    local config_files=("supabase-api.conf" "supabase-studio.conf" "n8n.conf")
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$nginx_dir/conf/$config_file" ]]; then
            log_info "Updating SSL paths in $config_file"
            
            # Update certificate paths in configuration
            sed -i "s|ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;|ssl_certificate ${ssl_cert_path};|g" "$nginx_dir/conf/$config_file"
            sed -i "s|ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;|ssl_certificate_key ${ssl_key_path};|g" "$nginx_dir/conf/$config_file"
            
            log_success "Updated SSL paths in $config_file"
        else
            log_warning "Configuration file not found: $config_file"
        fi
    done
    
    end_section_timer "NGINX SSL Config Update"
    log_success "NGINX SSL configuration updated successfully"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 SSL VALIDATION AND TESTING
# ═══════════════════════════════════════════════════════════════════════════════

# Validate SSL setup and certificate installation
validate_ssl_setup() {
    log_section "Validating SSL Setup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate SSL setup"
        return 0
    fi
    
    start_section_timer "SSL Validation"
    
    local validation_failed=false
    local domains_to_test=("${DOMAIN}" "${SUPABASE_SUBDOMAIN}.${DOMAIN}" "${STUDIO_SUBDOMAIN}.${DOMAIN}" "${N8N_SUBDOMAIN}.${DOMAIN}")
    
    # Wait for NGINX to be fully operational
    log_info "Waiting for NGINX to become operational..."
    sleep 10
    
    for domain in "${domains_to_test[@]}"; do
        log_info "Testing SSL connection to $domain"
        
        # Test SSL connection
        if curl -Is --connect-timeout 10 "https://$domain" | head -n 1 | grep -q "200 OK\|301 Moved\|302 Found"; then
            log_success "SSL connection successful for $domain"
            
            # Check certificate details
            local cert_info
            cert_info=$(openssl s_client -servername "$domain" -connect "$domain:443" -verify_return_error </dev/null 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
            
            if [[ -n "$cert_info" ]]; then
                log_info "Certificate info for $domain:"
                echo "$cert_info" | while read -r line; do
                    log_info "  $line"
                done
            fi
        else
            log_error "SSL connection failed for $domain"
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "SSL validation failed for one or more domains"
        end_section_timer "SSL Validation"
        return 1
    fi
    
    end_section_timer "SSL Validation"
    log_success "SSL setup validation completed successfully"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 CERTIFICATE RENEWAL SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

# Setup automatic certificate renewal
setup_certificate_renewal() {
    log_section "Setting up Automatic Certificate Renewal"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup automatic certificate renewal"
        return 0
    fi
    
    start_section_timer "Certificate Renewal Setup"
    
    # Create renewal script
    cat > /tmp/renew-certificates.sh << 'EOF'
#!/bin/bash
# SSL Certificate Renewal Script for COMPASS Stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

log_info "Starting SSL certificate renewal check"

# Renewal function
renew_certificates() {
    local nginx_dir="$BASE_DIR/services/nginx"
    
    # Check if certificates need renewal (Let's Encrypt auto-checks expiry)
    if docker run --rm -v $nginx_dir/certbot/conf:/etc/letsencrypt -v $nginx_dir/certbot/www:/var/www/certbot -v $nginx_dir/logs:/var/log/certbot certbot/certbot:v2.7.4 renew --quiet; then
        log_info "Certificate renewal check completed successfully"
        
        # Copy renewed certificates to NGINX directory
        if docker run --rm -v $nginx_dir/certbot/conf:/etc/letsencrypt -v $nginx_dir/ssl:/ssl alpine:latest cp -r /etc/letsencrypt/live/${DOMAIN}/ /ssl/live/ 2>/dev/null; then
            log_info "Renewed certificates copied to NGINX directory"
            
            # Reload NGINX to use new certificates
            if docker exec nginx-proxy nginx -s reload 2>/dev/null; then
                log_success "NGINX reloaded with renewed certificates"
            else
                log_warning "Failed to reload NGINX - manual restart may be required"
            fi
        else
            log_info "No certificates were renewed"
        fi
    else
        log_error "Certificate renewal failed"
        return 1
    fi
}

# Main renewal execution
renew_certificates
EOF
    
    # Install renewal script
    local script_dir="$BASE_DIR/scripts"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $script_dir" "Create scripts directory"
    safe_mv "/tmp/renew-certificates.sh" "$script_dir/renew-certificates.sh" "Install renewal script"
    safe_chmod "755" "$script_dir/renew-certificates.sh" "Make renewal script executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$script_dir/renew-certificates.sh" "Set renewal script ownership"
    
    # Create systemd timer for renewal (if systemd is available)
    if [[ -d "/etc/systemd/system" ]]; then
        log_info "Setting up systemd timer for certificate renewal"
        
        # Create service file
        cat > /tmp/jarvis-ssl-renewal.service << EOF
[Unit]
Description=COMPASS Stack SSL Certificate Renewal
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/renew-certificates.sh
StandardOutput=journal
StandardError=journal
EOF
        
        # Create timer file
        cat > /tmp/jarvis-ssl-renewal.timer << EOF
[Unit]
Description=Run COMPASS Stack SSL renewal twice daily
Requires=jarvis-ssl-renewal.service

[Timer]
OnCalendar=*-*-* 02,14:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        # Install systemd files
        safe_mv "/tmp/jarvis-ssl-renewal.service" "/etc/systemd/system/jarvis-ssl-renewal.service" "Install renewal service"
        safe_mv "/tmp/jarvis-ssl-renewal.timer" "/etc/systemd/system/jarvis-ssl-renewal.timer" "Install renewal timer"
        
        # Enable and start timer
        execute_cmd "systemctl daemon-reload" "Reload systemd daemon"
        execute_cmd "systemctl enable jarvis-ssl-renewal.timer" "Enable SSL renewal timer"
        execute_cmd "systemctl start jarvis-ssl-renewal.timer" "Start SSL renewal timer"
        
        log_success "Systemd timer configured for automatic certificate renewal"
    else
        log_warning "Systemd not available - manual certificate renewal required"
        log_info "Run $script_dir/renew-certificates.sh manually for certificate renewal"
    fi
    
    end_section_timer "Certificate Renewal Setup"
    log_success "Certificate renewal system setup completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 NGINX STARTUP WITH SSL
# ═══════════════════════════════════════════════════════════════════════════════

# Start NGINX container with SSL certificates configured
start_nginx_with_ssl() {
    log_section "Starting NGINX with SSL Certificates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would start NGINX with SSL certificates"
        return 0
    fi
    
    start_section_timer "NGINX SSL Startup"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    
    # Start NGINX and certbot containers
    log_info "Starting NGINX and certbot containers"
    if docker_cmd "cd $nginx_dir && docker-compose up -d" "Start NGINX with SSL"; then
        # Wait for NGINX to be healthy
        wait_for_service_health "nginx-proxy" 60 5
        log_success "NGINX started successfully with SSL configuration"
    else
        log_error "Failed to start NGINX with SSL configuration"
        end_section_timer "NGINX SSL Startup"
        return 1
    fi
    
    end_section_timer "NGINX SSL Startup"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN SSL ORCHESTRATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Configure SSL certificates (main function called from jstack.sh)
configure_ssl_certificates() {
    log_section "SSL Certificate Configuration Workflow"
    
    # Initialize timing
    init_timing_system
    
    # Step 1: Validate domain resolution
    if ! validate_domain_resolution; then
        log_error "Domain validation failed - SSL setup cannot proceed"
        return 1
    fi
    
    # Step 2: Check for existing valid certificates
    if check_existing_certificates; then
        log_info "Valid SSL certificates already exist - updating NGINX configuration"
        if update_nginx_ssl_config && validate_ssl_setup; then
            log_success "SSL certificates are already configured and working"
            return 0
        else
            log_warning "Existing certificates found but SSL validation failed - proceeding with renewal"
        fi
    fi
    
    # Step 3: Create temporary certificates for NGINX startup
    if ! create_temporary_certificates; then
        log_error "Failed to create temporary certificates"
        return 1
    fi
    
    # Step 4: Update NGINX config to use temporary certificates
    if ! update_nginx_ssl_config; then
        log_error "Failed to update NGINX SSL configuration"
        return 1
    fi
    
    # Step 5: Acquire Let's Encrypt certificates
    if ! setup_letsencrypt_certificates; then
        log_error "Failed to setup Let's Encrypt certificates"
        log_warning "NGINX will continue running with temporary self-signed certificates"
        return 1
    fi
    
    # Step 6: Update NGINX configuration with Let's Encrypt certificates
    if ! update_nginx_ssl_config; then
        log_error "Failed to update NGINX configuration with Let's Encrypt certificates"
        return 1
    fi
    
    # Step 7: Validate SSL setup
    if ! validate_ssl_setup; then
        log_error "SSL validation failed"
        return 1
    fi
    
    # Step 8: Start NGINX with SSL certificates
    if ! start_nginx_with_ssl; then
        log_error "Failed to start NGINX with SSL certificates"
        return 1
    fi
    
    # Step 9: Setup automatic renewal
    if ! setup_certificate_renewal; then
        log_warning "Failed to setup automatic certificate renewal - manual renewal required"
    fi
    
    log_success "SSL certificate configuration completed successfully"
    return 0
}

# Renew existing certificates (called manually or by cron/systemd)
renew_ssl_certificates() {
    log_section "SSL Certificate Renewal"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would renew SSL certificates"
        return 0
    fi
    
    start_section_timer "Certificate Renewal"
    
    # Source the renewal script functionality
    local nginx_dir="$BASE_DIR/services/nginx"
    
    # Check if certificates need renewal and renew them
    if docker run --rm -v $nginx_dir/certbot/conf:/etc/letsencrypt -v $nginx_dir/certbot/www:/var/www/certbot -v $nginx_dir/logs:/var/log/certbot certbot/certbot:v2.7.4 renew; then
        log_info "Certificate renewal completed"
        
        # Copy renewed certificates and reload NGINX
        if copy_certificates_to_nginx && docker exec nginx-proxy nginx -s reload 2>/dev/null; then
            log_success "Certificates renewed and NGINX reloaded successfully"
        else
            log_warning "Certificate renewal completed but NGINX reload failed"
        fi
    else
        log_info "No certificates required renewal"
    fi
    
    end_section_timer "Certificate Renewal"
    return 0
}

# Check SSL certificate status
check_ssl_status() {
    log_section "SSL Certificate Status"
    
    local nginx_dir="$BASE_DIR/services/nginx"
    local ssl_dir="$nginx_dir/ssl"
    
    # Check if certificates exist
    if [[ -f "$ssl_dir/live/${DOMAIN}/fullchain.pem" ]]; then
        local cert_info
        cert_info=$(openssl x509 -in "$ssl_dir/live/${DOMAIN}/fullchain.pem" -noout -text 2>/dev/null)
        
        if [[ -n "$cert_info" ]]; then
            local cert_subject
            local cert_expiry
            local cert_issuer
            
            cert_subject=$(echo "$cert_info" | grep "Subject:" | head -n1)
            cert_expiry=$(echo "$cert_info" | grep "Not After" | head -n1)
            cert_issuer=$(echo "$cert_info" | grep "Issuer:" | head -n1)
            
            echo "SSL Certificate Status:"
            echo "  $cert_subject"
            echo "  $cert_expiry"
            echo "  $cert_issuer"
            
            # Check expiry
            local expiry_date
            expiry_date=$(echo "$cert_expiry" | sed 's/.*Not After : //')
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
            local current_epoch
            current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
            
            if [[ $days_until_expiry -gt 0 ]]; then
                echo "  Certificate expires in $days_until_expiry days"
                if [[ $days_until_expiry -lt 30 ]]; then
                    echo "  ⚠️  Certificate renewal recommended"
                else
                    echo "  ✅ Certificate is valid"
                fi
            else
                echo "  ❌ Certificate has expired!"
            fi
        else
            echo "SSL Certificate Status: Unable to read certificate information"
        fi
    else
        echo "SSL Certificate Status: No certificates found"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-configure}" in
        "configure"|"setup")
            configure_ssl_certificates
            ;;
        "renew")
            renew_ssl_certificates
            ;;
        "status"|"check")
            check_ssl_status
            ;;
        "validate")
            validate_ssl_setup
            ;;
        *)
            echo "Usage: $0 [configure|renew|status|validate]"
            echo ""
            echo "Commands:"
            echo "  configure - Setup SSL certificates (default)"
            echo "  renew     - Renew existing certificates"
            echo "  status    - Check certificate status and expiry"
            echo "  validate  - Test SSL connections"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi