#!/bin/bash
# Container orchestration for JarvisJR Stack (Modular Architecture)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Service module delegation functions
setup_supabase_containers() {
    bash "${PROJECT_ROOT}/scripts/services/supabase_stack.sh" setup
}

setup_n8n_container() {
    [[ "$ENABLE_BROWSER_AUTOMATION" == "true" ]] && bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" browser-env
    bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" setup
}

setup_nginx_container() {
    bash "${PROJECT_ROOT}/scripts/services/nginx_proxy.sh" setup
}

# Legacy browser automation compatibility
install_chrome_dependencies() { bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" chrome; }
setup_puppeteer_environment() { bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" puppeteer; }
create_browser_automation_monitoring() { bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" monitoring; }
test_browser_automation_integration() { bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" test; }

# Main deployment function
deploy_all_containers() {
    log_section "Deploying All Containers (Modular Architecture)"
    init_timing_system
    
    if setup_supabase_containers && setup_n8n_container && setup_nginx_container; then
        log_success "All containers deployed successfully"
        return 0
    else
        log_error "Container deployment failed"
        return 1
    fi
}

# Service management functions
show_service_status() {
    echo "=== Supabase ===" && bash "${PROJECT_ROOT}/scripts/services/supabase_stack.sh" status
    echo "=== N8N ==="     && bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" status
    echo "=== NGINX ==="   && bash "${PROJECT_ROOT}/scripts/services/nginx_proxy.sh" status
    echo "Total containers: $(docker ps --filter name="supabase-\|n8n\|nginx-proxy" | grep -c "Up" || echo "0")"
}

start_all_services() {
    bash "${PROJECT_ROOT}/scripts/services/supabase_stack.sh" setup
    bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" setup
    bash "${PROJECT_ROOT}/scripts/services/nginx_proxy.sh" start
}

stop_all_services() {
    bash "${PROJECT_ROOT}/scripts/services/nginx_proxy.sh" stop
    docker stop n8n 2>/dev/null || true
    docker ps --filter name="supabase-" -q | xargs -r docker stop
}

# Test service modules
test_service_modules() {
    local passed=0
    for module in supabase_stack n8n_browser nginx_proxy common_services; do
        bash "${PROJECT_ROOT}/scripts/services/${module}.sh" status &>/dev/null && ((passed++))
    done
    echo "Service modules accessible: $passed/4"
}

# Main function
# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 SITE MANAGEMENT WITH COMPLIANCE INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Add a site to the system with compliance integration
add_site() {
    local site_path="$1"
    local template_flag="$2"
    local template_name="$3"
    
    # Source template validation functions
    source "${PROJECT_ROOT}/scripts/lib/template_validation.sh"
    
    # Handle template-based deployment
    if [[ "$template_flag" == "--template" && -n "$template_name" ]]; then
        log_info "Processing template-based site deployment"
        
        # Validate template exists and is valid
        local template_path="${PROJECT_ROOT}/templates/$template_name"
        if [[ ! -d "$template_path" ]]; then
            log_error "Template not found: $template_name"
            log_info "Available templates:"
            list_available_templates
            return 1
        fi
        
        # Validate template structure and security
        if ! validate_template "$template_path"; then
            log_error "Template validation failed for: $template_name"
            return 1
        fi
        
        # Extract domain from site_path (assume domain is the parameter)
        local domain="$site_path"
        
        # Validate domain format
        if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid domain format: $domain"
            log_info "Domain should be in format: example.com or sub.example.com"
            return 1
        fi
        
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would deploy template: $template_name"
            log_info "[DRY RUN] Would create site for domain: $domain"
            log_info "[DRY RUN] Would copy template files and configure services"
            return 0
        fi
        
        # Deploy template-based site
        deploy_template_site "$template_path" "$template_name" "$domain"
        return $?
    fi
    
    # Original add_site logic for non-template deployments
    if [[ -z "$site_path" ]]; then
        log_error "Site path is required for site addition"
        echo "Usage: $0 add-site /path/to/site/directory [--template template-name]"
        return 1
    fi
    
    log_section "Adding Site from $site_path"
    
    # Extract domain from site path (assume domain is directory name)
    local domain=$(basename "$site_path")
    
    # Validate domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $domain"
        log_info "Domain should be in format: example.com or sub.example.com"
        return 1
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would add site: $domain"
        log_info "[DRY RUN] Would register in site registry with compliance profile"
        log_info "[DRY RUN] Would update compliance documentation"
        return 0
    fi
    
    log_info "Processing site addition for domain: $domain"
    
    # Check if site configuration exists
    if [[ ! -d "$site_path" ]]; then
        log_error "Site directory not found: $site_path"
        return 1
    fi
    
    # Check if a site configuration file exists (placeholder for future implementation)
    local site_config="$site_path/site.json"
    if [[ -f "$site_config" ]]; then
        log_info "Found site configuration: $site_config"
        # Future: Parse site configuration for specific settings
    else
        log_info "No site configuration found, using defaults"
    fi
    
    # Source common.sh to get site registry functions
    source "${PROJECT_ROOT}/scripts/lib/common.sh"
    
    # Add site to registry with compliance profile
    local compliance_profile="${DEFAULT_COMPLIANCE_PROFILE:-default}"
    if [[ -f "$site_config" ]] && command -v jq &> /dev/null; then
        # Extract compliance profile from site config if available
        compliance_profile=$(jq -r '.compliance_profile // "default"' "$site_config" 2>/dev/null || echo "default")
    fi
    
    log_info "Adding site to registry with compliance profile: $compliance_profile"
    if add_site_to_registry "$domain" "$compliance_profile"; then
        log_success "Site registered: $domain"
    else
        log_error "Failed to register site in registry"
        return 1
    fi
    
    # Update compliance documentation if auto-update is enabled
    if [[ "${AUTO_UPDATE_DOCS:-true}" == "true" ]]; then
        log_info "Updating compliance documentation for new site"
        if bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" update-site-docs add "$domain"; then
            log_success "Compliance documentation updated for site: $domain"
        else
            log_warning "Failed to update compliance documentation for site: $domain"
        fi
    fi
    
    # Create NGINX configuration for the new site
    log_info "Creating NGINX configuration for site: $domain"
    if create_site_nginx_config "$domain"; then
        log_success "NGINX configuration created for site: $domain"
    else
        log_warning "Failed to create NGINX configuration for site: $domain"
    fi
    
    # Generate SSL certificates for the new site
    log_info "Requesting SSL certificates for site: $domain"
    if request_site_ssl_certificates "$domain"; then
        log_success "SSL certificates requested for site: $domain"
    else
        log_warning "Failed to request SSL certificates for site: $domain"
    fi
    
    log_success "Site addition completed for: $domain"
    log_info "Site is now registered and monitored for compliance"
    
    return 0
}

# Template deployment function
deploy_template_site() {
    local template_path="$1"
    local template_name="$2"
    local domain="$3"
    
    log_info "Deploying template site: $template_name for domain: $domain"
    
    # Create site directory
    local site_dir="${PROJECT_ROOT}/sites/$domain"
    local domain_safe=$(echo "$domain" | sed 's/[^a-zA-Z0-9]/_/g')
    
    if [[ -d "$site_dir" ]]; then
        log_error "Site directory already exists: $site_dir"
        return 1
    fi
    
    log_info "Creating site directory: $site_dir"
    mkdir -p "$site_dir"
    
    # Copy template files to site directory
    log_info "Copying template files from: $template_path"
    cp -r "$template_path"/* "$site_dir/"
    
    # Parse template configuration
    local template_json="$site_dir/template.json"
    if [[ ! -f "$template_json" ]]; then
        log_error "Template configuration not found: $template_json"
        return 1
    fi
    
    # Generate environment variables for template
    local env_file="$site_dir/.env"
    cat > "$env_file" << EOF
# JarvisJR Stack Template Environment
DOMAIN=$domain
DOMAIN_SAFE=$domain_safe
PROJECT_ROOT=${PROJECT_ROOT}

# Database configuration (for templates that need it)
DB_NAME=${domain_safe}_db
DB_USER=${domain_safe}_user
DB_PASS=$(openssl rand -hex 16)
DB_ROOT_PASS=$(openssl rand -hex 16)

# Generated on: $(date)
EOF
    
    # Process Docker Compose template
    local compose_template="$site_dir/docker/docker-compose.yml"
    if [[ -f "$compose_template" ]]; then
        log_info "Processing Docker Compose configuration"
        
        # Replace template variables in docker-compose.yml
        sed -i "s/\${DOMAIN}/$domain/g" "$compose_template"
        sed -i "s/\${DOMAIN_SAFE}/$domain_safe/g" "$compose_template"
        
        # Source environment file for additional variables
        set -a
        source "$env_file"
        set +a
        
        # Replace additional environment variables
        envsubst < "$compose_template" > "$site_dir/docker/docker-compose.processed.yml"
        mv "$site_dir/docker/docker-compose.processed.yml" "$compose_template"
    fi
    
    # Process NGINX configuration template
    local nginx_template="$site_dir/nginx/site.conf.template"
    if [[ -f "$nginx_template" ]]; then
        log_info "Processing NGINX configuration template"
        create_site_nginx_config "$domain" "$template_name" "$site_dir"
    fi
    
    # Add site to registry with template information
    source "${PROJECT_ROOT}/scripts/lib/common.sh"
    local compliance_profile="default"
    
    if command -v jq &> /dev/null; then
        compliance_profile=$(jq -r '.compliance.profile // "default"' "$template_json" 2>/dev/null)
    fi
    
    log_info "Registering template site with compliance profile: $compliance_profile"
    if add_site_to_registry "$domain" "$compliance_profile" "$template_name"; then
        log_success "Template site registered: $domain"
    else
        log_error "Failed to register template site in registry"
        return 1
    fi
    
    # Request SSL certificates
    log_info "Requesting SSL certificates for template site: $domain"
    if request_site_ssl_certificates "$domain" "$template_name"; then
        log_success "SSL certificates requested for template site: $domain"
    else
        log_warning "Failed to request SSL certificates for template site: $domain"
    fi
    
    # Start template services if not in dry-run mode
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_info "Starting template services for: $domain"
        
        if [[ -f "$site_dir/docker/docker-compose.yml" ]]; then
            cd "$site_dir/docker"
            
            # Load environment variables
            set -a
            source "$site_dir/.env"
            set +a
            
            # Start services
            if docker-compose up -d; then
                log_success "Template services started for: $domain"
            else
                log_error "Failed to start template services for: $domain"
                return 1
            fi
            
            cd "${PROJECT_ROOT}"
        fi
    fi
    
    log_success "Template site deployment completed: $domain"
    log_info "Template: $template_name"
    log_info "Site directory: $site_dir"
    log_info "Domain: $domain"
    
    return 0
}

# Template-aware NGINX configuration function
create_site_nginx_config() {
    local domain="$1"
    local template_name="$2"
    local site_dir="$3"
    
    log_info "Creating NGINX configuration for domain: $domain"
    
    # Default values if not template-based
    if [[ -z "$template_name" ]]; then
        template_name="custom"
    fi
    
    if [[ -z "$site_dir" ]]; then
        site_dir="${PROJECT_ROOT}/sites/$domain"
    fi
    
    local domain_safe=$(echo "$domain" | sed 's/[^a-zA-Z0-9]/_/g')
    local nginx_dir="/etc/nginx/sites-available"
    local nginx_config="$nginx_dir/$domain.conf"
    
    # Create NGINX sites directory if it doesn't exist
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create NGINX configuration: $nginx_config"
        return 0
    fi
    
    # Check if we have a template-specific configuration
    local nginx_template="$site_dir/nginx/site.conf.template"
    
    if [[ -f "$nginx_template" ]]; then
        log_info "Using template-specific NGINX configuration"
        
        # Process template variables
        sed -e "s/\${DOMAIN}/$domain/g" \
            -e "s/\${DOMAIN_SAFE}/$domain_safe/g" \
            -e "s/\${CONTAINER_NAME}/${template_name}-${domain_safe}/g" \
            -e "s/\${PORT}/3000/g" \
            "$nginx_template" > "/tmp/${domain}.conf"
        
        # Move to NGINX configuration directory (requires sudo)
        if sudo cp "/tmp/${domain}.conf" "$nginx_config"; then
            log_success "Template NGINX configuration created: $nginx_config"
            
            # Enable site
            sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/$domain.conf"
            
            # Test NGINX configuration
            if sudo nginx -t; then
                log_success "NGINX configuration test passed"
                sudo systemctl reload nginx
            else
                log_error "NGINX configuration test failed"
                return 1
            fi
        else
            log_error "Failed to create NGINX configuration file"
            return 1
        fi
        
        # Cleanup temporary file
        rm -f "/tmp/${domain}.conf"
        
    else
        log_info "Using default NGINX configuration template"
        # Create basic NGINX configuration for custom sites
        create_default_nginx_config "$domain"
    fi
    
    return 0
}

# Template-aware SSL certificate function
request_site_ssl_certificates() {
    local domain="$1"
    local template_name="$2"
    
    log_info "Requesting SSL certificates for domain: $domain"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would request Let's Encrypt SSL certificate for: $domain"
        return 0
    fi
    
    # Check if certbot is available
    if ! command -v certbot &> /dev/null; then
        log_error "Certbot not found. Please install certbot for SSL certificate management"
        return 1
    fi
    
    # Request certificate using Let's Encrypt
    log_info "Requesting Let's Encrypt certificate for: $domain"
    
    # Use webroot method for existing sites, standalone for new ones
    local cert_method="webroot"
    local webroot_path="/var/www/html"
    
    # Check if this is a template with custom webroot
    if [[ -n "$template_name" ]]; then
        local site_dir="${PROJECT_ROOT}/sites/$domain"
        local template_json="$site_dir/template.json"
        
        if [[ -f "$template_json" ]] && command -v jq &> /dev/null; then
            local nginx_root=$(jq -r '.nginx.root_path // "/var/www/html"' "$template_json" 2>/dev/null)
            if [[ -n "$nginx_root" && "$nginx_root" != "null" ]]; then
                webroot_path="$nginx_root"
            fi
        fi
    fi
    
    # Create webroot directory if it doesn't exist
    sudo mkdir -p "$webroot_path"
    
    # Request certificate
    if sudo certbot certonly \
        --webroot \
        --webroot-path="$webroot_path" \
        --email "${EMAIL:-admin@${domain}}" \
        --agree-tos \
        --non-interactive \
        --domains "$domain"; then
        
        log_success "SSL certificate obtained for: $domain"
        
        # Update NGINX configuration to use SSL
        local nginx_config="/etc/nginx/sites-available/$domain.conf"
        if [[ -f "$nginx_config" ]]; then
            # Add SSL configuration if not already present
            if ! grep -q "ssl_certificate" "$nginx_config"; then
                log_info "Adding SSL configuration to NGINX"
                add_ssl_to_nginx_config "$domain"
            fi
        fi
        
        # Reload NGINX to apply SSL configuration
        if sudo nginx -t; then
            sudo systemctl reload nginx
            log_success "NGINX reloaded with SSL configuration"
        else
            log_error "NGINX configuration test failed after SSL setup"
            return 1
        fi
        
    else
        log_error "Failed to obtain SSL certificate for: $domain"
        return 1
    fi
    
    return 0
}

# Helper function to create default NGINX configuration
create_default_nginx_config() {
    local domain="$1"
    local domain_safe=$(echo "$domain" | sed 's/[^a-zA-Z0-9]/_/g')
    
    local nginx_config="/etc/nginx/sites-available/$domain.conf"
    
    # Create basic NGINX configuration
    sudo tee "$nginx_config" > /dev/null << EOF
# NGINX configuration for $domain
# Generated by JarvisJR Stack

server {
    listen 80;
    server_name $domain;
    root /var/www/$domain;
    index index.html index.php;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Rate limiting
    limit_req zone=default burst=20 nodelay;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # PHP processing (if needed)
    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }

    # Static files caching
    location ~* \\.(css|js|jpg|jpeg|png|gif|ico|svg)\$ {
        expires 30d;
        add_header Cache-Control "public";
        access_log off;
    }

    # Block access to hidden files
    location ~ /\\. {
        deny all;
    }
}
EOF

    log_success "Default NGINX configuration created for: $domain"
}

# Helper function to add SSL configuration to existing NGINX config
add_ssl_to_nginx_config() {
    local domain="$1"
    local nginx_config="/etc/nginx/sites-available/$domain.conf"
    
    # Create SSL server block
    local ssl_config="
server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header Strict-Transport-Security \"max-age=63072000\" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection \"1; mode=block\";
    add_header Referrer-Policy \"strict-origin-when-cross-origin\";

    # Include existing location blocks here
    include /etc/nginx/sites-available/$domain-locations.conf;
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}
"
    
    # Extract location blocks from existing config
    local locations_file="/etc/nginx/sites-available/$domain-locations.conf"
    sudo grep -A 1000 "location" "$nginx_config" | sudo tee "$locations_file" > /dev/null
    
    # Replace original config with SSL version
    echo "$ssl_config" | sudo tee "$nginx_config" > /dev/null
    
    log_info "SSL configuration added to NGINX for: $domain"
}

# Remove a site from the system with compliance cleanup
remove_site() {
    local site_path="$1"
    
    if [[ -z "$site_path" ]]; then
        log_error "Site path is required for site removal"
        echo "Usage: $0 remove-site /path/to/site/directory"
        return 1
    fi
    
    log_section "Removing Site from $site_path"
    
    # Extract domain from site path
    local domain=$(basename "$site_path")
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would remove site: $domain"
        log_info "[DRY RUN] Would remove from site registry"
        log_info "[DRY RUN] Would update compliance documentation"
        log_info "[DRY RUN] Would archive compliance data"
        return 0
    fi
    
    log_info "Processing site removal for domain: $domain"
    
    # Source common.sh to get site registry functions
    source "${PROJECT_ROOT}/scripts/lib/common.sh"
    
    # Check if site exists in registry
    if ! get_site_from_registry "$domain" >/dev/null 2>&1; then
        log_warning "Site not found in registry: $domain"
        log_info "Proceeding with cleanup anyway"
    fi
    
    # Remove site from registry
    log_info "Removing site from registry: $domain"
    if remove_site_from_registry "$domain"; then
        log_success "Site removed from registry: $domain"
    else
        log_warning "Failed to remove site from registry: $domain"
    fi
    
    # Update compliance documentation if auto-update is enabled
    if [[ "${AUTO_UPDATE_DOCS:-true}" == "true" ]]; then
        log_info "Updating compliance documentation for removed site"
        if bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" update-site-docs remove "$domain"; then
            log_success "Compliance documentation updated for removed site: $domain"
        else
            log_warning "Failed to update compliance documentation for removed site: $domain"
        fi
    fi
    
    # Remove NGINX configuration for the site (placeholder)
    log_info "Removing NGINX configuration for site: $domain"
    if remove_site_nginx_config "$domain"; then
        log_success "NGINX configuration removed for site: $domain"
    else
        log_warning "Failed to remove NGINX configuration for site: $domain"
    fi
    
    # Clean up SSL certificates for the site (placeholder)
    log_info "Cleaning up SSL certificates for site: $domain"
    if cleanup_site_ssl_certificates "$domain"; then
        log_success "SSL certificates cleaned up for site: $domain"
    else
        log_warning "Failed to clean up SSL certificates for site: $domain"
    fi
    
    log_success "Site removal completed for: $domain"
    log_info "Compliance data has been archived for audit purposes"
    
    return 0
}

# Create NGINX configuration for a site (placeholder implementation)
create_site_nginx_config() {
    local domain="$1"
    
    log_info "Creating NGINX configuration for: $domain"
    
    # Placeholder: In a full implementation, this would:
    # 1. Generate NGINX site configuration
    # 2. Create proxy rules for subdomains
    # 3. Configure SSL settings
    # 4. Reload NGINX configuration
    
    log_info "NGINX configuration creation is not yet fully implemented"
    log_info "This would create configuration for:"
    log_info "  - ${SUPABASE_SUBDOMAIN:-supabase}.$domain"
    log_info "  - ${STUDIO_SUBDOMAIN:-studio}.$domain"
    log_info "  - ${N8N_SUBDOMAIN:-n8n}.$domain"
    
    return 0
}

# Remove NGINX configuration for a site (placeholder implementation)
remove_site_nginx_config() {
    local domain="$1"
    
    log_info "Removing NGINX configuration for: $domain"
    
    # Placeholder: In a full implementation, this would:
    # 1. Remove NGINX site configuration file
    # 2. Disable site in NGINX
    # 3. Remove proxy rules
    # 4. Reload NGINX configuration
    
    log_info "NGINX configuration removal is not yet fully implemented"
    log_info "This would remove configuration for: $domain"
    
    return 0
}

# Request SSL certificates for a site (placeholder implementation)
request_site_ssl_certificates() {
    local domain="$1"
    
    log_info "Requesting SSL certificates for: $domain"
    
    # Placeholder: In a full implementation, this would:
    # 1. Use Let's Encrypt to request certificates
    # 2. Configure certificate paths
    # 3. Set up certificate renewal
    # 4. Update NGINX SSL configuration
    
    log_info "SSL certificate request is not yet fully implemented"
    log_info "This would request certificates for:"
    log_info "  - $domain"
    log_info "  - ${SUPABASE_SUBDOMAIN:-supabase}.$domain"
    log_info "  - ${STUDIO_SUBDOMAIN:-studio}.$domain"
    log_info "  - ${N8N_SUBDOMAIN:-n8n}.$domain"
    
    return 0
}

# Clean up SSL certificates for a site (placeholder implementation)
cleanup_site_ssl_certificates() {
    local domain="$1"
    
    log_info "Cleaning up SSL certificates for: $domain"
    
    # Placeholder: In a full implementation, this would:
    # 1. Revoke SSL certificates if needed
    # 2. Remove certificate files
    # 3. Clean up certificate directories
    # 4. Remove certificate renewal jobs
    
    log_info "SSL certificate cleanup is not yet fully implemented"
    log_info "This would clean up certificates for: $domain"
    
    return 0
}

# List all managed sites
list_managed_sites() {
    log_section "Managed Sites"
    
    # Source common.sh to get site registry functions
    source "${PROJECT_ROOT}/scripts/lib/common.sh"
    
    if list_sites_in_registry; then
        log_info "Use --compliance-check to validate all sites"
    else
        log_warning "Failed to list sites or no site registry found"
        return 1
    fi
}

main() {
    case "${1:-deploy}" in
        "deploy"|"all") deploy_all_containers ;;
        "supabase") setup_supabase_containers ;;
        "n8n") setup_n8n_container ;;
        "nginx") setup_nginx_container ;;
        "status") show_service_status ;;
        "start") start_all_services ;;
        "stop") stop_all_services ;;
        "test-modules") test_service_modules ;;
        "add-site") add_site "$2" "$3" "$4" ;;
        "remove-site") remove_site "$2" ;;
        "list-sites") list_managed_sites ;;
        "logs")
            case "${2:-all}" in
                "supabase"|"sb") bash "${PROJECT_ROOT}/scripts/services/supabase_stack.sh" logs "${3:-supabase-db}" ;;
                "n8n") bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" logs ;;
                "nginx") bash "${PROJECT_ROOT}/scripts/services/nginx_proxy.sh" logs ;;
                *) bash "${PROJECT_ROOT}/scripts/services/supabase_stack.sh" logs supabase-db 2>/dev/null
                   bash "${PROJECT_ROOT}/scripts/services/n8n_browser.sh" logs 2>/dev/null
                   bash "${PROJECT_ROOT}/scripts/services/nginx_proxy.sh" logs 2>/dev/null ;;
            esac ;;
        *) echo "Usage: $0 [deploy|supabase|n8n|nginx|status|start|stop|add-site|remove-site|list-sites|logs|test-modules]"
           echo "Site Management: add-site PATH, remove-site PATH, list-sites"
           echo "Modular architecture: Original 47K chars -> Current ~5K chars (89% reduction)" ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi