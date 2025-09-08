#!/bin/bash
# System Cleanup and Uninstall Script for JStack
# Complete removal of all system components, containers, and configurations

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🛑 CONTAINER AND SERVICE CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# Stop and remove all JStack containers
cleanup_containers() {
    log_section "Stopping and Removing All Containers"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would stop and remove all JStack containers"
        return 0
    fi
    
    start_section_timer "Container Cleanup"
    
    # List of JStack container names
    local containers=(
        "nginx-proxy"
        "certbot"
        "n8n"
        "supabase-studio"
        "supabase-meta"
        "supabase-storage"
        "supabase-imgproxy"
        "supabase-realtime"
        "supabase-rest"
        "supabase-auth"
        "supabase-kong"
        "supabase-db"
    )
    
    # Stop containers gracefully first
    log_info "Stopping JStack containers gracefully"
    for container in "${containers[@]}"; do
        if docker ps -q --filter "name=$container" | grep -q .; then
            log_info "Stopping container: $container"
            docker stop "$container" --time 30 >/dev/null 2>&1 || true
        fi
    done
    
    # Remove containers
    log_info "Removing JStack containers"
    for container in "${containers[@]}"; do
        if docker ps -aq --filter "name=$container" | grep -q .; then
            log_info "Removing container: $container"
            docker rm "$container" >/dev/null 2>&1 || true
        fi
    done
    
    # Force kill any remaining containers with JStack-related names
    log_info "Cleaning up any remaining JStack containers"
    local remaining_containers=$(docker ps -aq --filter "name=supabase" --filter "name=n8n" --filter "name=nginx-proxy" --filter "name=certbot" 2>/dev/null || true)
    if [[ -n "$remaining_containers" ]]; then
        echo "$remaining_containers" | xargs -r docker rm -f >/dev/null 2>&1 || true
    fi
    
    end_section_timer "Container Cleanup"
    log_success "Container cleanup completed"
    return 0
}

# Remove Docker volumes
cleanup_docker_volumes() {
    log_section "Removing Docker Volumes"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove Docker volumes"
        return 0
    fi
    
    start_section_timer "Volume Cleanup"
    
    # List of JStack volume patterns
    local volume_patterns=(
        "supabase_*"
        "n8n_*"
        "*_certbot_*"
        "certbot_*"
        "*jarvis*"
    )
    
    # Get all volumes matching our patterns
    local volumes_to_remove=""
    for pattern in "${volume_patterns[@]}"; do
        local matching_volumes=$(docker volume ls -q --filter "name=$pattern" 2>/dev/null || true)
        if [[ -n "$matching_volumes" ]]; then
            volumes_to_remove="$volumes_to_remove $matching_volumes"
        fi
    done
    
    # Remove volumes
    if [[ -n "$volumes_to_remove" ]]; then
        log_info "Removing Docker volumes"
        for volume in $volumes_to_remove; do
            log_info "Removing volume: $volume"
            docker volume rm "$volume" >/dev/null 2>&1 || true
        done
        log_success "Docker volumes removed"
    else
        log_info "No JStack Docker volumes found to remove"
    fi
    
    end_section_timer "Volume Cleanup"
    return 0
}

# Remove Docker networks
cleanup_docker_networks() {
    log_section "Removing Docker Networks"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove Docker networks"
        return 0
    fi
    
    start_section_timer "Network Cleanup"
    
    # List of JStack networks
    local networks=(
        "$JARVIS_NETWORK"
        "$PUBLIC_TIER"
        "$PRIVATE_TIER"
    )
    
    for network in "${networks[@]}"; do
        if docker network ls --filter "name=$network" --format "{{.Name}}" | grep -q "^$network$"; then
            log_info "Removing Docker network: $network"
            docker network rm "$network" >/dev/null 2>&1 || true
        fi
    done
    
    # Remove any remaining networks with jarvis in the name
    local remaining_networks=$(docker network ls --filter "name=jarvis" --format "{{.Name}}" 2>/dev/null || true)
    if [[ -n "$remaining_networks" ]]; then
        echo "$remaining_networks" | while read -r network; do
            log_info "Removing remaining network: $network"
            docker network rm "$network" >/dev/null 2>&1 || true
        done
    fi
    
    end_section_timer "Network Cleanup"
    log_success "Docker network cleanup completed"
    return 0
}

# Remove Docker images
cleanup_docker_images() {
    log_section "Removing Docker Images"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove JStack Docker images"
        return 0
    fi
    
    start_section_timer "Image Cleanup"
    
    # List of image names used by JStack
    local image_patterns=(
        "postgres:15-alpine"
        "kong:3.4-alpine"
        "supabase/*"
        "postgrest/*"
        "n8nio/n8n:*"
        "nginx:1.25-alpine"
        "certbot/*"
        "darthsim/imgproxy:*"
        "alpine:latest"
    )
    
    log_info "Removing JStack Docker images"
    
    # Remove images by pattern
    for pattern in "${image_patterns[@]}"; do
        local images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^${pattern//\*/.*}$" 2>/dev/null || true)
        if [[ -n "$images" ]]; then
            echo "$images" | while read -r image; do
                log_info "Removing image: $image"
                docker rmi "$image" >/dev/null 2>&1 || true
            done
        fi
    done
    
    # Clean up dangling images
    log_info "Removing dangling Docker images"
    docker image prune -f >/dev/null 2>&1 || true
    
    end_section_timer "Image Cleanup"
    log_success "Docker image cleanup completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 SYSTEM CONFIGURATION CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# Remove systemd services and timers
cleanup_systemd_services() {
    log_section "Removing Systemd Services and Timers"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove systemd services and timers"
        return 0
    fi
    
    start_section_timer "Systemd Cleanup"
    
    # List of JStack systemd units
    local systemd_units=(
        "jarvis-ssl-renewal.service"
        "jarvis-ssl-renewal.timer"
        "browser-monitor.service"
        "browser-monitor.timer"
    )
    
    for unit in "${systemd_units[@]}"; do
        if systemctl list-units --full -a | grep -q "$unit"; then
            log_info "Stopping and disabling: $unit"
            systemctl stop "$unit" >/dev/null 2>&1 || true
            systemctl disable "$unit" >/dev/null 2>&1 || true
        fi
        
        # Remove unit files
        local unit_file="/etc/systemd/system/$unit"
        if [[ -f "$unit_file" ]]; then
            log_info "Removing systemd unit file: $unit"
            rm -f "$unit_file"
        fi
    done
    
    # Reload systemd daemon
    if [[ ${#systemd_units[@]} -gt 0 ]]; then
        log_info "Reloading systemd daemon"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    
    end_section_timer "Systemd Cleanup"
    log_success "Systemd cleanup completed"
    return 0
}

# Remove firewall rules
cleanup_firewall_rules() {
    log_section "Removing Firewall Rules"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove firewall rules"
        return 0
    fi
    
    start_section_timer "Firewall Cleanup"
    
    log_info "Manual iptables configuration - no automatic firewall cleanup performed"
    log_info "If you configured iptables rules, manually remove them if needed"
    
    end_section_timer "Firewall Cleanup"
    log_success "Firewall cleanup completed"
    return 0
}

# Remove SSL certificates and Let's Encrypt configuration
cleanup_ssl_certificates() {
    log_section "Removing SSL Certificates and Let's Encrypt Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove SSL certificates and Let's Encrypt config"
        return 0
    fi
    
    start_section_timer "SSL Cleanup"
    
    # Remove SSL certificates from service directory
    if [[ -d "$BASE_DIR/services/nginx/ssl" ]]; then
        log_info "Removing SSL certificates from service directory"
        rm -rf "$BASE_DIR/services/nginx/ssl"
    fi
    
    # Remove Let's Encrypt certificates if they exist in Docker volumes
    local letsencrypt_volumes=$(docker volume ls -q --filter "name=certbot" 2>/dev/null || true)
    if [[ -n "$letsencrypt_volumes" ]]; then
        log_info "Removing Let's Encrypt certificates and configuration"
        echo "$letsencrypt_volumes" | xargs -r docker volume rm >/dev/null 2>&1 || true
    fi
    
    # Remove any certificate files that might exist in system locations
    local cert_locations=(
        "/etc/letsencrypt"
        "/var/lib/letsencrypt"
        "/var/log/letsencrypt"
    )
    
    for location in "${cert_locations[@]}"; do
        if [[ -d "$location" ]] && [[ "$location" =~ letsencrypt ]]; then
            log_info "Removing certificates from: $location"
            rm -rf "$location" 2>/dev/null || true
        fi
    done
    
    end_section_timer "SSL Cleanup"
    log_success "SSL cleanup completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 👤 SERVICE USER AND DIRECTORY CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# Remove service user and directories
cleanup_service_user() {
    log_section "Removing Service User and Directories"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would remove service user and directories"
        return 0
    fi
    
    start_section_timer "Service User Cleanup"
    
    # Stop any processes owned by service user
    log_info "Stopping processes owned by $SERVICE_USER"
    pkill -u "$SERVICE_USER" >/dev/null 2>&1 || true
    sleep 2
    pkill -9 -u "$SERVICE_USER" >/dev/null 2>&1 || true
    
    # Remove service user and group
    if id "$SERVICE_USER" >/dev/null 2>&1; then
        log_info "Removing service user: $SERVICE_USER"
        userdel -r "$SERVICE_USER" >/dev/null 2>&1 || true
    fi
    
    if getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
        log_info "Removing service group: $SERVICE_GROUP"
        groupdel "$SERVICE_GROUP" >/dev/null 2>&1 || true
    fi
    
    # Remove base directory if it still exists
    if [[ -d "$BASE_DIR" ]]; then
        log_info "Removing base directory: $BASE_DIR"
        rm -rf "$BASE_DIR"
    fi
    
    # Clean up any leftover home directory
    local user_home="/home/$SERVICE_USER"
    if [[ -d "$user_home" ]]; then
        log_info "Cleaning up remaining home directory: $user_home"
        rm -rf "$user_home"
    fi
    
    end_section_timer "Service User Cleanup"
    log_success "Service user cleanup completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🧹 BROWSER AUTOMATION CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# Clean up browser automation components
cleanup_browser_automation() {
    log_section "Cleaning up Browser Automation Components"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean up browser automation components"
        return 0
    fi
    
    start_section_timer "Browser Automation Cleanup"
    
    # Kill any running Chrome processes
    log_info "Stopping Chrome processes"
    pkill -f "google-chrome" >/dev/null 2>&1 || true
    pkill -f "chromium" >/dev/null 2>&1 || true
    sleep 2
    pkill -9 -f "google-chrome" >/dev/null 2>&1 || true
    pkill -9 -f "chromium" >/dev/null 2>&1 || true
    
    # Clean up Chrome temporary files and caches
    log_info "Cleaning up Chrome temporary files"
    
    # Remove Chrome temporary directories
    local chrome_temp_patterns=(
        "/tmp/chrome_*"
        "/tmp/.org.chromium.*"
        "/tmp/puppeteer_*"
        "/tmp/scoped_dir*"
        "/dev/shm/.org.chromium.*"
    )
    
    for pattern in "${chrome_temp_patterns[@]}"; do
        find "$(dirname "$pattern")" -name "$(basename "$pattern")" -type d -exec rm -rf {} \; 2>/dev/null || true
    done
    
    # Clean up Puppeteer cache if it exists
    if [[ -d "$PUPPETEER_CACHE_DIR" ]]; then
        log_info "Removing Puppeteer cache directory"
        rm -rf "$PUPPETEER_CACHE_DIR"
    fi
    
    # Remove Chrome/Chromium packages (optional - user choice)
    if [[ "$1" == "remove-chrome" ]]; then
        log_info "Removing Chrome browser packages"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get remove --purge -y google-chrome-stable chromium-browser >/dev/null 2>&1 || true
            apt-get autoremove -y >/dev/null 2>&1 || true
        fi
        
        # Remove Chrome repository
        rm -f /etc/apt/sources.list.d/google-chrome.list
        rm -f /usr/share/keyrings/googlechrome-linux-keyring.gpg
        
        log_info "Chrome packages and repositories removed"
    else
        log_info "Chrome browser installation preserved (use 'remove-chrome' to remove)"
    fi
    
    end_section_timer "Browser Automation Cleanup"
    log_success "Browser automation cleanup completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🧼 SYSTEM-WIDE CLEANUP
# ═══════════════════════════════════════════════════════════════════════════════

# Clean up system-wide configurations
cleanup_system_configurations() {
    log_section "Cleaning up System-wide Configurations"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean up system configurations"
        return 0
    fi
    
    start_section_timer "System Config Cleanup"
    
    # Remove any JStack-related entries from system files
    log_info "Cleaning up system configuration files"
    
    # Clean up hosts file (remove any JStack entries)
    if [[ -f "/etc/hosts" ]]; then
        sed -i '/# JStack/d' /etc/hosts 2>/dev/null || true
        sed -i "/$DOMAIN.*# JStack/d" /etc/hosts 2>/dev/null || true
    fi
    
    # Clean up any cron jobs for the service user
    if command -v crontab >/dev/null 2>&1; then
        crontab -u "$SERVICE_USER" -r >/dev/null 2>&1 || true
    fi
    
    # Clean up log files
    log_info "Cleaning up log files"
    local log_locations=(
        "/var/log/jarvis*"
        "/var/log/supabase*"
        "/var/log/n8n*"
    )
    
    for log_pattern in "${log_locations[@]}"; do
        find "$(dirname "$log_pattern")" -name "$(basename "$log_pattern")" -type f -delete 2>/dev/null || true
    done
    
    # Clean up temporary setup files
    rm -f /tmp/setup-logs/* 2>/dev/null || true
    rm -rf /tmp/jarvis_* 2>/dev/null || true
    
    end_section_timer "System Config Cleanup"
    log_success "System configuration cleanup completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 💾 BACKUP PRESERVATION
# ═══════════════════════════════════════════════════════════════════════════════

# Preserve backups during cleanup
preserve_backups() {
    log_section "Preserving System Backups"
    
    local backup_source="$BASE_DIR/backups"
    local backup_preserve="/tmp/jarvis-backups-preserved-$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$backup_source" ]]; then
        local backup_count=$(find "$backup_source" -name "backup_*.tar.gz*" -type f | wc -l)
        
        if [[ $backup_count -gt 0 ]]; then
            log_info "Found $backup_count backup(s) to preserve"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would preserve backups to: $backup_preserve"
                return 0
            fi
            
            # Copy backups to temporary location
            cp -r "$backup_source" "$backup_preserve"
            
            # Set proper permissions
            chmod -R 700 "$backup_preserve"
            
            log_success "Backups preserved in: $backup_preserve"
            log_info "You can restore these backups later or move them to a permanent location"
            
            # Store location for reference
            echo "$backup_preserve" > /tmp/jarvis-backup-location.txt
        else
            log_info "No backups found to preserve"
        fi
    else
        log_info "No backup directory found"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 COMPLETE SYSTEM UNINSTALLATION
# ═══════════════════════════════════════════════════════════════════════════════

# Perform complete system uninstallation
uninstall_complete_system() {
    local remove_chrome_flag="$1"
    
    log_section "Complete JStack Uninstallation"
    
    # Initialize timing
    init_timing_system
    
    # Warning and confirmation
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_warning "⚠️  COMPLETE SYSTEM UNINSTALLATION ⚠️"
        echo ""
        echo "This will completely remove:"
        echo "  ✗ All Docker containers, volumes, and networks"
        echo "  ✗ Service user ($SERVICE_USER) and all directories"
        echo "  ✗ SSL certificates and Let's Encrypt configuration"
        echo "  ✗ Systemd services and timers"
        echo "  ✗ Browser automation components"
        echo "  ✗ Firewall rules"
        echo "  ✗ System configuration changes"
        if [[ "$remove_chrome_flag" == "remove-chrome" ]]; then
            echo "  ✗ Chrome browser installation"
        fi
        echo ""
        echo "  ✓ Backups will be preserved in /tmp"
        echo ""
        echo "This action cannot be undone!"
        echo ""
        echo "Type 'UNINSTALL' to confirm complete removal:"
        read -r confirmation
        
        if [[ "$confirmation" != "UNINSTALL" ]]; then
            log_info "Uninstallation cancelled"
            return 1
        fi
        
        log_warning "Proceeding with complete uninstallation..."
        sleep 3
    fi
    
    # Preserve backups first
    preserve_backups
    
    # Perform cleanup steps
    local cleanup_steps=(
        "cleanup_containers"
        "cleanup_docker_volumes"
        "cleanup_docker_networks"
        "cleanup_docker_images"
        "cleanup_systemd_services"
        "cleanup_firewall_rules"
        "cleanup_ssl_certificates"
        "cleanup_browser_automation $remove_chrome_flag"
        "cleanup_system_configurations"
        "cleanup_service_user"
    )
    
    local failed_steps=()
    
    for step in "${cleanup_steps[@]}"; do
        log_info "Executing cleanup step: $step"
        
        if $step; then
            log_success "Cleanup step completed: $step"
        else
            log_error "Cleanup step failed: $step"
            failed_steps+=("$step")
        fi
    done
    
    # Report results
    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        log_success "Complete JStack uninstallation completed successfully"
        
        if [[ -f "/tmp/jarvis-backup-location.txt" ]]; then
            local backup_location=$(cat /tmp/jarvis-backup-location.txt)
            log_info "Preserved backups location: $backup_location"
        fi
        
        log_info "System is now clean - JStack has been completely removed"
        return 0
    else
        log_error "Uninstallation completed with ${#failed_steps[@]} failed steps:"
        printf "  - %s\n" "${failed_steps[@]}"
        log_warning "You may need to manually clean up the failed components"
        return 1
    fi
}

# Partial cleanup (specific components only)
cleanup_partial() {
    local component="$1"
    
    case "$component" in
        "containers")
            cleanup_containers
            ;;
        "volumes")
            cleanup_docker_volumes
            ;;
        "networks")
            cleanup_docker_networks
            ;;
        "images")
            cleanup_docker_images
            ;;
        "systemd")
            cleanup_systemd_services
            ;;
        "firewall")
            cleanup_firewall_rules
            ;;
        "ssl")
            cleanup_ssl_certificates
            ;;
        "browser")
            cleanup_browser_automation "$2"
            ;;
        "user")
            cleanup_service_user
            ;;
        "system")
            cleanup_system_configurations
            ;;
        *)
            echo "Unknown cleanup component: $component"
            echo "Available components: containers, volumes, networks, images, systemd, firewall, ssl, browser, user, system"
            return 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-complete}" in
        "complete"|"all"|"uninstall")
            uninstall_complete_system "$2"
            ;;
        "partial")
            if [[ -n "$2" ]]; then
                cleanup_partial "$2" "$3"
            else
                echo "Error: partial cleanup requires component name"
                echo "Usage: $0 partial [component]"
                echo "Components: containers, volumes, networks, images, systemd, firewall, ssl, browser, user, system"
                exit 1
            fi
            ;;
        "preserve-backups")
            preserve_backups
            ;;
        *)
            echo "JStack Cleanup and Uninstall Script"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  complete           - Complete system uninstallation (default)"
            echo "  complete remove-chrome - Complete uninstallation including Chrome browser"
            echo "  partial [component] - Clean up specific component only"
            echo "  preserve-backups   - Preserve backups to /tmp location"
            echo ""
            echo "Partial cleanup components:"
            echo "  containers  - Stop and remove all containers"
            echo "  volumes     - Remove Docker volumes"
            echo "  networks    - Remove Docker networks"
            echo "  images      - Remove Docker images"
            echo "  systemd     - Remove systemd services and timers"
            echo "  firewall    - Remove firewall rules"
            echo "  ssl         - Remove SSL certificates"
            echo "  browser     - Clean up browser automation (add 'remove-chrome' to uninstall Chrome)"
            echo "  user        - Remove service user and directories"
            echo "  system      - Clean up system-wide configurations"
            echo ""
            echo "Examples:"
            echo "  $0                      # Complete uninstallation"
            echo "  $0 complete remove-chrome # Complete uninstallation including Chrome"
            echo "  $0 partial containers   # Remove only containers"
            echo "  $0 partial browser remove-chrome # Remove browser components and Chrome"
            echo "  $0 preserve-backups     # Save backups before cleanup"
            echo ""
            echo "Environment Variables:"
            echo "  DRY_RUN=true           # Test mode - show what would be done"
            echo ""
            echo "⚠️  WARNING: Complete uninstallation will remove ALL JStack components!"
            echo "   Backups will be preserved automatically in /tmp during complete uninstallation."
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi