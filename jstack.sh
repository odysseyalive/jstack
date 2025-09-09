#!/bin/bash
# JStack - Main Orchestrator Script
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
    # Initialize system first to load configuration
    initialize_system
    
    log_section "Starting JStack Installation"
    
    # Phase 0: Sudo Access Validation (Fail Fast)
    log_info "Phase 0: Sudo Access Validation"
    source "${PROJECT_ROOT}/scripts/lib/validation.sh"
    if ! validate_sudo_access; then
        log_error "Sudo access validation failed"
        log_info "Please configure sudo access and try again:"
        log_info "  ./jstack.sh --configure-sudo"
        log_info "  ./jstack.sh --force-install  # Force with password prompts"
        return 1
    fi
    
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
    
    log_success "JStack installation completed successfully!"
    
    # Display access information
    show_access_information
}

# Uninstallation workflow
run_uninstallation() {
    log_section "Starting JStack Uninstallation"
    
    # Load configuration first to ensure variables are available for dry-run
    source "${PROJECT_ROOT}/scripts/settings/config.sh"
    load_config
    export_config
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would completely remove JStack installation including:"
        log_info "[DRY-RUN]   • All Docker containers and volumes"
        log_info "[DRY-RUN]   • Service user ($SERVICE_USER) and directories ($BASE_DIR)"
        log_info "[DRY-RUN]   • SSL certificates from Let's Encrypt"
        log_info "[DRY-RUN]   • UFW firewall rules (ports 80, 443)"
        log_info "[DRY-RUN]   • System configurations and services"
        log_info "[DRY-RUN]   • Preserving backups in $BASE_DIR/backups"
        log_info "[DRY-RUN] Interactive confirmation bypassed in dry-run mode"
        return 0
    fi
    
    log_warning "This will completely remove the JStack installation"
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
        log_success "JStack uninstallation completed successfully"
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

# Sudo configuration workflow
run_sudo_configuration() {
    log_section "Configuring Passwordless Sudo"
    if ! bash "${PROJECT_ROOT}/scripts/core/setup.sh" sudo; then
        log_error "Sudo configuration failed"
        return 1
    fi
}

# Docker uninstallation workflow
run_docker_uninstall() {
    log_section "Docker Uninstallation"
    
    # Initialize system to load common functions
    initialize_system
    
    # Source setup.sh to get the uninstall function
    source "${PROJECT_ROOT}/scripts/core/setup.sh"
    
    log_warning "This will completely remove Docker and all containers/images/volumes"
    log_warning "All Docker data will be permanently deleted"
    
    if prompt_yes_no "Are you sure you want to uninstall Docker?"; then
        uninstall_existing_docker
        log_success "Docker has been uninstalled"
        log_info "You can now run './jstack.sh' to install Docker with proper JarvisJR configuration"
    else
        log_info "Docker uninstallation cancelled"
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
        log_info "Reports available in: ${BASE_DIR}/opt/jstack-security/compliance-reports/"
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
    
    echo "Your JStack is now running and accessible at:"
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
    
    echo "Your JStack is now running and accessible at:"
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
JStack - Production-ready containerized deployment system

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
  --force-install    Force installation even with password-based sudo
  --configure-ssl    Configure SSL certificates and start NGINX
  --configure-sudo   Configure passwordless sudo for SERVICE_USER
  --uninstall-docker Remove existing Docker installation for clean reinstall
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
  $0 --force-install # Force installation with password-based sudo (not recommended)
  $0 --configure-ssl # Configure SSL certificates and start NGINX
  $0 --configure-sudo # Configure passwordless sudo for service user

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

# Show dry-run summary of what would be done
show_dry_run_summary() {
    # Initialize system first to load configuration
    initialize_system
    
    log_section "🧪 Dry-Run Summary - What Would Be Done"
    
    echo "📋 JStack Installation Summary (DRY-RUN MODE):"
    echo ""
    
    echo "🏗️  SYSTEM SETUP PHASE:"
    echo "   • Validate system requirements (Docker, UFW, etc.)"
    echo "   • Create service user: $SERVICE_USER"
    echo "   • Create base directory: $BASE_DIR"
    echo "   • Set up logging: $BASE_DIR/logs/"
    echo "   • Configure firewall rules (ports 80, 443, 22)"
    echo ""
    
    echo "🐳 CONTAINER DEPLOYMENT PHASE:"
    echo "   • Deploy PostgreSQL container with optimized settings"
    echo "   • Deploy Supabase Stack (API + Studio + Edge Functions)"
    echo "   • Deploy N8N workflow automation container"
    echo "   • Deploy Chrome browser automation container"
    echo "   • Configure Docker networks for service isolation"
    echo ""
    
    echo "🔒 SSL CONFIGURATION PHASE:"
    echo "   • Request Let's Encrypt certificates for:"
    echo "     - ${SUPABASE_SUBDOMAIN}.${DOMAIN}"
    echo "     - ${STUDIO_SUBDOMAIN}.${DOMAIN}"
    echo "     - ${N8N_SUBDOMAIN}.${DOMAIN}"
    echo "   • Configure NGINX reverse proxy"
    echo "   • Set up automatic certificate renewal"
    echo ""
    
    echo "🔄 SERVICE ORCHESTRATION PHASE:"
    echo "   • Start all containers in dependency order"
    echo "   • Wait for service health checks"
    echo "   • Initialize database schemas"
    echo "   • Configure inter-service authentication"
    echo "   • Validate complete system functionality"
    echo ""
    
    echo "📊 EXPECTED RESOURCES:"
    echo "   • Disk Space: ~2GB for containers + logs/backups"
    echo "   • Memory Usage: ~6GB total (PostgreSQL: 4GB, N8N: 2GB, Chrome: 4GB)"
    echo "   • Network Ports: 80 (HTTP), 443 (HTTPS)"
    echo "   • Service User: $SERVICE_USER with limited privileges"
    echo ""
    
    echo "🌐 ACCESS ENDPOINTS (Post-Installation):"
    echo "   • Supabase API: https://${SUPABASE_SUBDOMAIN}.${DOMAIN}"
    echo "   • Supabase Studio: https://${STUDIO_SUBDOMAIN}.${DOMAIN}"
    echo "   • N8N Workflows: https://${N8N_SUBDOMAIN}.${DOMAIN}"
    echo ""
    
    echo "💡 TO PROCEED WITH ACTUAL INSTALLATION:"
    echo "   Run: $0 --install"
    echo ""
    echo "💡 TO TEST SPECIFIC OPERATIONS:"
    echo "   • Backup: $0 --dry-run --backup [name]"
    echo "   • Uninstall: $0 --dry-run --uninstall"
    echo "   • SSL Config: $0 --dry-run --configure-ssl"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN COMMAND LINE PARSING
# ═══════════════════════════════════════════════════════════════════════════════

# Parse command-line arguments
main() {
    # Initialize tracking variables
    local operation=""
    local operation_args=()
    local dry_run_enabled=false
    
    # Process command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_usage
                exit 0
                ;;
            --install)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="install"
                shift
                ;;
            --uninstall)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="uninstall"
                shift
                ;;
            --reset)
                # Legacy support for --reset flag
                echo "Warning: --reset is deprecated, use --uninstall instead"
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="uninstall"
                shift
                ;;
            --backup)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="backup"
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    operation_args=("$2")
                    shift 2
                else
                    shift
                fi
                ;;
            --restore)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="restore"
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    operation_args=("$2")
                    shift 2
                else
                    shift
                fi
                ;;
            --list-backups)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="list-backups"
                shift
                ;;
            --sync)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="sync"
                shift
                ;;
            --configure-ssl)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="configure-ssl"
                shift
                ;;
            --configure-sudo)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="configure-sudo"
                shift
                ;;
            --uninstall-docker)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="uninstall-docker"
                shift
                ;;
            --compliance-check)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                operation="compliance-check"
                shift
                ;;
            --add-site)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                if [[ -z "$2" ]]; then
                    echo "Error: --add-site requires a path or domain"
                    echo "Usage: $0 --add-site /path/to/site/directory"
                    echo "       $0 --add-site domain.com --template template-name"
                    exit 1
                fi
                operation="add-site"
                
                # Check for template flag
                if [[ "$3" == "--template" && -n "$4" ]]; then
                    operation_args=("$2" "$4")
                    shift 4
                else
                    operation_args=("$2")
                    shift 2
                fi
                ;;
            --remove-site)
                if [[ -n "$operation" ]]; then
                    echo "Error: Multiple operations specified. Use one at a time."
                    exit 1
                fi
                if [[ -z "$2" ]]; then
                    echo "Error: --remove-site requires a path to site configuration"
                    echo "Usage: $0 --remove-site /path/to/site/directory"
                    exit 1
                fi
                operation="remove-site"
                operation_args=("$2")
                shift 2
                ;;
            --dry-run)
                export DRY_RUN="true"
                dry_run_enabled=true
                log_info "Dry-run mode enabled"
                shift
                ;;
            --force-install)
                export FORCE_INSTALL="true"
                log_info "Force install mode enabled (will proceed with password-based sudo)"
                shift
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
    
    # Handle dry-run standalone operation
    if [[ "$dry_run_enabled" == true && -z "$operation" ]]; then
        show_dry_run_summary
        exit 0
    fi
    
    # Execute the specified operation or default to installation
    case "$operation" in
        "install")
            run_installation
            ;;
        "uninstall")
            run_uninstallation
            ;;
        "backup")
            if [[ ${#operation_args[@]} -gt 0 ]]; then
                run_backup "${operation_args[0]}"
            else
                run_backup
            fi
            ;;
        "restore")
            if [[ ${#operation_args[@]} -gt 0 ]]; then
                run_restore "${operation_args[0]}"
            else
                run_restore
            fi
            ;;
        "list-backups")
            list_backups
            ;;
        "sync")
            run_sync
            ;;
        "configure-ssl")
            run_ssl_configuration
            ;;
        "configure-sudo")
            run_sudo_configuration
            ;;
        "uninstall-docker")
            run_docker_uninstall
            ;;
        "compliance-check")
            run_compliance_check
            ;;
        "add-site")
            if [[ ${#operation_args[@]} -eq 2 ]]; then
                add_site "${operation_args[0]}" "${operation_args[1]}"
            else
                add_site "${operation_args[0]}"
            fi
            ;;
        "remove-site")
            remove_site "${operation_args[0]}"
            ;;
        *)
            # Default action if no operation specified
            run_installation
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎬 SCRIPT ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi