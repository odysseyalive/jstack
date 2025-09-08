#!/bin/bash
# JarvisJR Stack - Main Orchestrator Script
# Production-ready containerized deployment system for AI productivity tools
#
# This script serves as the unified CLI interface and orchestrates all modular components
# All business logic resides in scripts/ subdirectories - this file only routes commands
#
# NOTE: All module calls use 'bash script.sh' instead of './script.sh' to work
# regardless of executable permissions on the module files

set -e # Exit on any error

# Get script directory and set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source common utilities first (config loading will happen after arg parsing)
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Function to initialize configuration and logging (called after arg parsing)
initialize_system() {
    source "${PROJECT_ROOT}/scripts/settings/config.sh"
    load_config
    export_config
    setup_logging
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 COMMAND ROUTING FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Main installation workflow
run_installation() {
    log_section "Starting JarvisJR Stack Installation"
    
    # Phase 1: System Setup
    log_info "Phase 1: System Setup and Validation"
    if ! bash "${PROJECT_ROOT}/scripts/core/setup.sh" run; then
        log_error "System setup failed"
        return 1
    fi
    
    # Phase 2: Container Deployment
    log_info "Phase 2: Container Deployment"
    if ! bash "${PROJECT_ROOT}/scripts/core/containers.sh" deploy; then
        log_error "Container deployment failed"
        return 1
    fi
    
    # Phase 3: SSL Configuration
    log_info "Phase 3: SSL Configuration"
    if ! bash "${PROJECT_ROOT}/scripts/core/ssl.sh" configure; then
        log_error "SSL configuration failed"
        return 1
    fi
    
    # Phase 4: Service Orchestration and Final Health Checks
    log_info "Phase 4: Service Orchestration and Health Validation"
    if bash "${PROJECT_ROOT}/scripts/core/service_orchestration.sh" start-all; then
        log_success "All services started and validated successfully"
    else
        log_warning "Some services may have issues - check logs for details"
    fi
    
    log_success "JarvisJR Stack installation completed successfully!"
    
    # Display access information
    show_access_information
}

# Uninstallation workflow
run_uninstallation() {
    log_section "Starting JarvisJR Stack Uninstallation"
    
    log_warning "This will completely remove the JarvisJR Stack installation"
    echo "This includes:"
    echo "- All Docker containers and volumes"
    echo "- Service user and directories"
    echo "- SSL certificates"
    echo "- Firewall rules"
    echo "- System configurations"
    echo ""
    echo "Backups in $BASE_DIR/backups will be preserved."
    echo ""
    echo "Are you sure you want to continue? (y/N)"
    read -r confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
    
    # Execute complete uninstallation
    if bash "${PROJECT_ROOT}/scripts/utils/cleanup.sh" complete; then
        log_success "JarvisJR Stack uninstallation completed successfully"
    else
        log_error "Uninstallation failed or completed with warnings"
        log_info "Check logs for details or run manual cleanup if needed"
        return 1
    fi
}

# Backup workflow
run_backup() {
    local backup_name="$1"
    log_section "Creating System Backup"
    
    if [[ -n "$backup_name" ]]; then
        log_info "Creating named backup: $backup_name"
    else
        log_info "Creating timestamped backup"
    fi
    
    # Execute backup functionality
    if bash "${PROJECT_ROOT}/scripts/core/backup.sh" create "$backup_name"; then
        log_success "System backup completed successfully"
    else
        log_error "System backup failed"
        return 1
    fi
}

# Restore workflow  
run_restore() {
    local restore_file="$1"
    log_section "Restoring System Backup"
    
    if [[ -n "$restore_file" ]]; then
        log_info "Restoring from: $restore_file"
    else
        log_info "Interactive restore mode"
    fi
    
    # Execute restore functionality
    if bash "${PROJECT_ROOT}/scripts/core/backup.sh" restore "$restore_file"; then
        log_success "System restore completed successfully"
        log_info "You may need to restart services after restore"
    else
        log_error "System restore failed"
        return 1
    fi
}

# SSL configuration workflow
run_ssl_configuration() {
    log_section "Configuring SSL Certificates"
    if ! bash "${PROJECT_ROOT}/scripts/core/ssl.sh" configure; then
        log_error "SSL configuration failed"
        return 1
    fi
}

# Compliance check workflow
run_compliance_check() {
    log_section "Running Compliance Check"
    
    if ! bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" validate; then
        log_error "Compliance validation failed"
        return 1
    fi
    
    if bash "${PROJECT_ROOT}/scripts/security/compliance_monitoring.sh" regenerate-reports; then
        log_success "Compliance check completed successfully"
        log_info "Reports available in: ${BASE_DIR}/opt/jarvis-security/compliance-reports/"
    else
        log_error "Compliance report generation failed"
        return 1
    fi
}

# Site management workflows
add_site() {
    local site_path="$1"
    local template_name="$2"
    
    log_section "Adding Site"
    
    # Handle template-based deployment
    if [[ -n "$template_name" ]]; then
        log_info "Adding site using template: $template_name"
        log_info "Target domain/path: $site_path"
        
        # Execute template-based site addition via containers.sh
        if bash "${PROJECT_ROOT}/scripts/core/containers.sh" add-site "$site_path" --template "$template_name"; then
            log_success "Template-based site addition completed successfully"
        else
            log_error "Template-based site addition failed"
            return 1
        fi
    else
        log_info "Adding site from: $site_path"
        
        # Execute standard site addition via containers.sh
        if bash "${PROJECT_ROOT}/scripts/core/containers.sh" add-site "$site_path"; then
            log_success "Site addition completed successfully"
        else
            log_error "Site addition failed"
            return 1
        fi
    fi
}

remove_site() {
    local site_path="$1"
    log_section "Removing Site"
    log_info "Removing site: $site_path"
    
    # Execute site removal via containers.sh
    if bash "${PROJECT_ROOT}/scripts/core/containers.sh" remove-site "$site_path"; then
        log_success "Site removal completed successfully"
    else
        log_error "Site removal failed"
        return 1
    fi
}

# List backups
list_backups() {
    log_section "Available Backups"
    
    if [[ -d "$BASE_DIR/backups" ]]; then
        local backup_files=("$BASE_DIR/backups"/backup_*.tar.gz*)
        if [[ ${#backup_files[@]} -gt 0 && -f "${backup_files[0]}" ]]; then
            echo "Found backups:"
            for backup in "${backup_files[@]}"; do
                if [[ -f "$backup" ]]; then
                    local size=$(du -h "$backup" | cut -f1)
                    local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
                    echo "  $(basename "$backup") - $size - $date"
                fi
            done
        else
            echo "No backups found in $BASE_DIR/backups"
        fi
    else
        echo "Backup directory does not exist: $BASE_DIR/backups"
    fi
}

# Show access information
show_access_information() {
    log_section "🎉 Installation Complete - Access Information"
    
    echo "Your JarvisJR Stack is now running and accessible at:"
    echo ""
    echo "🗄️  Supabase API:     https://${SUPABASE_SUBDOMAIN}.${DOMAIN}"
    echo "🎨  Supabase Studio:  https://${STUDIO_SUBDOMAIN}.${DOMAIN}"
    echo "🔄  N8N Workflows:    https://${N8N_SUBDOMAIN}.${DOMAIN}"
    echo ""
    echo "📊 Service Status:"
    if command -v docker &>/dev/null; then
        echo "   Containers: $(docker ps --format 'table {{.Names}}	{{.Status}}' | grep -c 'Up' || echo '0') running"
    fi
    echo ""
    echo "📝 Configuration:"
    echo "   Base Directory: $BASE_DIR"
    echo "   Service User: $SERVICE_USER"
    echo "   Logs: $BASE_DIR/logs"
    echo "   Backups: $BASE_DIR/backups"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Create backup: $0 --backup"
    echo "   View logs: tail -f $BASE_DIR/logs/setup_*.log"
    echo "   Check status: docker ps"
}

# Sync system workflows
run_sync() {
    log_section "Sync System Management"
    
    # Check if sync script exists
    if [[ ! -f "${PROJECT_ROOT}/scripts/core/sync.sh" ]]; then
        log_error "Sync script not found: scripts/core/sync.sh"
        log_info "This suggests an incomplete installation"
        return 1
    fi
    
    # Execute sync with update mode (for existing installations)
    if bash "${PROJECT_ROOT}/scripts/core/sync.sh" update; then
        log_success "System sync completed successfully"
    else
        log_error "System sync failed"
        return 1
    fi
}

# Show access information
show_access_information() {
    log_section "🎉 Installation Complete - Access Information"
    
    echo "Your JarvisJR Stack is now running and accessible at:"
    echo ""
    echo "🗄️  Supabase API:     https://${SUPABASE_SUBDOMAIN}.${DOMAIN}"
    echo "🎨  Supabase Studio:  https://${STUDIO_SUBDOMAIN}.${DOMAIN}"
    echo "🔄  N8N Workflows:    https://${N8N_SUBDOMAIN}.${DOMAIN}"
    echo ""
    echo "📊 Service Status:"
    if command -v docker &>/dev/null; then
        echo "   Containers: $(docker ps --format 'table {{.Names}}	{{.Status}}' | grep -c 'Up' || echo '0') running"
    fi
    echo ""
    echo "📝 Configuration:"
    echo "   Base Directory: $BASE_DIR"
    echo "   Service User: $SERVICE_USER"
    echo "   Logs: $BASE_DIR/logs"
    echo "   Backups: $BASE_DIR/backups"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Create backup: $0 --backup"
    echo "   View logs: tail -f $BASE_DIR/logs/setup_*.log"
    echo "   Check status: docker ps"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📋 HELP AND USAGE
# ═══════════════════════════════════════════════════════════════════════════════

show_usage() {
    cat << EOF
JarvisJR Stack - Production-ready containerized deployment system

USAGE:
  $0 [OPTION]

OPTIONS:
  --install          Run the installation (default)
  --uninstall        Uninstall/remove all installed components
  --backup [NAME]    Create complete system backup (optional custom name)
  --restore [FILE]   Restore from backup (interactive selection if no file)
  --list-backups     List all available backups with details
  --sync             Update system files from repository (preserves config)
  --dry-run          Run in dry-run mode (no actual changes)
  --configure-ssl    Configure SSL certificates and start NGINX
  --compliance-check Run compliance validation and generate reports
  --add-site PATH    Add a site from specified path
  --remove-site PATH Remove a site from specified path
  --enable-debug     Enable debug logging
  --help             Show this help message

EXAMPLES:
  $0                 # Default installation
  $0 --install       # Explicit installation
  $0 --uninstall     # Remove everything and uninstall
  $0 --backup        # Create timestamped backup
  $0 --backup pre-upgrade  # Create named backup
  $0 --restore       # Interactive restore selection
  $0 --restore backup_20250109_203045.tar.gz  # Restore specific backup
  $0 --list-backups  # Show all available backups
  $0 --sync          # Update scripts from repository (preserves config)
  $0 --add-site sites/example.com    # Add a site from config
  $0 --remove-site sites/example.com # Remove a site
  $0 --compliance-check # Run compliance validation and reports
  $0 --dry-run       # Test run without making changes
  $0 --configure-ssl # Configure SSL certificates and start NGINX

CONFIGURATION:
  Configuration files:
    jstack.config.default  - Default values (do not edit)
    jstack.config          - Your customizations (copy from default)
    
  Setup instructions:
    1. cp jstack.config.default jstack.config
    2. Edit jstack.config with your DOMAIN and EMAIL
    3. See README.md for detailed configuration guide

For more information, see the documentation in docs/
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN COMMAND LINE PARSING
# ═══════════════════════════════════════════════════════════════════════════════

# Parse command-line arguments
main() {
    # Handle help first (before config loading)
    for arg in "$@"; do
        case $arg in
            --help|-h)
                show_usage
                exit 0
                ;;
        esac
    done
    
    # Initialize system configuration and logging
    initialize_system
    
    # Set up signal handlers
    trap 'log_interrupted_exit' INT TERM
    trap 'log_failure_exit $LINENO $? "$BASH_COMMAND"' ERR
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install)
                run_installation
                exit 0
                ;;
            --uninstall)
                run_uninstallation
                exit 0
                ;;
            --reset)
                # Legacy support for --reset flag
                echo "Warning: --reset is deprecated, use --uninstall instead"
                run_uninstallation
                exit 0
                ;;
            --backup)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    run_backup "$2"
                    shift 2
                else
                    run_backup
                    shift
                fi
                exit 0
                ;;
            --restore)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    run_restore "$2"
                    shift 2
                else
                    run_restore
                    shift
                fi
                exit 0
                ;;
            --list-backups)
                list_backups
                exit 0
                ;;
            --sync)
                run_sync
                exit 0
                ;;
            --dry-run)
                export DRY_RUN="true"
                log_info "Dry-run mode enabled"
                shift
                ;;
            --configure-ssl)
                run_ssl_configuration
                exit 0
                ;;
            --compliance-check)
                run_compliance_check
                exit 0
                ;;
            --add-site)
                if [[ -z "$2" ]]; then
                    echo "Error: --add-site requires a path or domain"
                    echo "Usage: $0 --add-site /path/to/site/directory"
                    echo "       $0 --add-site domain.com --template template-name"
                    exit 1
                fi
                
                # Check for template flag
                if [[ "$3" == "--template" && -n "$4" ]]; then
                    add_site "$2" "$4"
                    shift 4
                else
                    add_site "$2"
                    shift 2
                fi
                exit 0
                ;;
            --remove-site)
                if [[ -z "$2" ]]; then
                    echo "Error: --remove-site requires a path to site configuration"
                    echo "Usage: $0 --remove-site /path/to/site/directory"
                    exit 1
                fi
                remove_site "$2"
                exit 0
                ;;
            --enable-debug)
                export ENABLE_DEBUG_LOGS="true"
                log_info "Debug logging enabled"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Default action if no arguments provided
    run_installation
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎬 SCRIPT ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi