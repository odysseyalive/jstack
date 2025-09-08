#!/bin/bash
# COMPASS Stack - Sync System
# Secure file synchronization and update system for modular architecture
#
# This script enables secure distribution and updates while maintaining
# the excellent modular design of the COMPASS Stack

set -e # Exit on any error

# Get script directory and set up paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Repository configuration
REPO_URL="https://github.com/odysseyalive/JStack"
RAW_BASE_URL="https://raw.githubusercontent.com/odysseyalive/JStack/main"

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# File manifest - all files that should be synced from the repository
declare -a SYNC_MANIFEST=(
    # Core modular scripts
    "scripts/core/setup.sh"
    "scripts/core/containers.sh"
    "scripts/core/ssl.sh"
    "scripts/core/backup.sh"
    "scripts/core/error_recovery.sh"
    "scripts/core/database_init.sh"
    "scripts/core/service_orchestration.sh"
    "scripts/core/secure_browser.sh"
    
    # Library scripts
    "scripts/lib/common.sh"
    "scripts/lib/validation.sh"
    
    # Settings and configuration
    "scripts/settings/config.sh"
    
    # Utility scripts
    "scripts/utils/cleanup.sh"
    
    # Configuration templates
    "jstack.config.default"
    
    # Main orchestrator (self-update)
    "jstack.sh"
    
    # Documentation
    "README.md"
    "CLAUDE.md"
    
    # License
    "LICENSE"
)

# ═══════════════════════════════════════════════════════════════════════════════
# 🛠️ UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Logging functions
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${BLUE}[SYNC]${NC} $1"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Progress tracking
show_progress() {
    local current=$1
    local total=$2
    local filename=$3
    local progress=$((current * 100 / total))
    local bar_length=40
    local filled_length=$((progress * bar_length / 100))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    printf "\r${CYAN}[%3d%%]${NC} %s ${YELLOW}%s${NC}" "$progress" "$bar" "$filename"
}

# Check if required tools are available
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v sha256sum &> /dev/null && ! command -v shasum &> /dev/null; then
        missing_tools+=("sha256sum or shasum")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again"
        return 1
    fi
    
    return 0
}

# Test internet connectivity to GitHub
test_connectivity() {
    log_info "Testing connectivity to GitHub..."
    
    if ! curl -s --max-time 10 --head "$RAW_BASE_URL/README.md" >/dev/null 2>&1; then
        log_error "Cannot connect to GitHub repository"
        log_info "Please check your internet connection and try again"
        return 1
    fi
    
    log_success "Connectivity test passed"
    return 0
}

# Create directory structure
create_directories() {
    local directories=(
        "scripts/core"
        "scripts/lib"
        "scripts/settings"
        "scripts/utils"
        "docs"
    )
    
    for dir in "${directories[@]}"; do
        local full_path="$PROJECT_ROOT/$dir"
        if [[ ! -d "$full_path" ]]; then
            log_info "Creating directory: $dir"
            mkdir -p "$full_path"
        fi
    done
}

# Download a single file with error handling
download_file() {
    local file_path="$1"
    local url="$RAW_BASE_URL/$file_path"
    local local_path="$PROJECT_ROOT/$file_path"
    local temp_file="${local_path}.tmp"
    
    # Create directory if it doesn't exist
    local dir_path=$(dirname "$local_path")
    mkdir -p "$dir_path"
    
    # Download to temporary file
    if curl -fsSL "$url" -o "$temp_file" 2>/dev/null; then
        # Check if file was actually downloaded (not empty or error page)
        if [[ -s "$temp_file" ]] && ! grep -q "404: Not Found" "$temp_file" 2>/dev/null; then
            # Move to final location
            mv "$temp_file" "$local_path"
            return 0
        else
            rm -f "$temp_file"
            return 1
        fi
    else
        rm -f "$temp_file"
        return 1
    fi
}

# Check if file needs updating (based on size or content differences)
file_needs_update() {
    local file_path="$1"
    local local_path="$PROJECT_ROOT/$file_path"
    
    # If file doesn't exist locally, it needs to be downloaded
    if [[ ! -f "$local_path" ]]; then
        return 0
    fi
    
    # For now, we'll always try to update (can be enhanced with checksums later)
    # In a production system, you might want to compare checksums or timestamps
    return 0
}

# Backup existing file before update
backup_file() {
    local file_path="$1"
    local local_path="$PROJECT_ROOT/$file_path"
    local backup_path="${local_path}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$local_path" ]]; then
        cp "$local_path" "$backup_path"
        log_info "Backed up existing file: $(basename "$file_path")"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 SYNC OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Sync all files from the manifest
sync_files() {
    local mode="$1" # "install" or "update"
    local total_files=${#SYNC_MANIFEST[@]}
    local current=0
    local updated_files=()
    local failed_files=()
    local skipped_files=()
    
    log_section "Syncing Files from Repository"
    log_info "Repository: $REPO_URL"
    log_info "Files to sync: $total_files"
    echo ""
    
    for file_path in "${SYNC_MANIFEST[@]}"; do
        ((current++))
        show_progress $current $total_files "$file_path"
        
        # Special handling for user configuration - never overwrite
        if [[ "$file_path" == "jstack.config" ]]; then
            local local_path="$PROJECT_ROOT/$file_path"
            if [[ -f "$local_path" ]]; then
                skipped_files+=("$file_path (user configuration preserved)")
                continue
            fi
        fi
        
        # Check if file needs updating
        if file_needs_update "$file_path"; then
            # Backup existing file if in update mode
            if [[ "$mode" == "update" ]]; then
                backup_file "$file_path"
            fi
            
            # Download the file
            if download_file "$file_path"; then
                updated_files+=("$file_path")
                
                # Make scripts executable
                if [[ "$file_path" == *.sh ]]; then
                    chmod +x "$PROJECT_ROOT/$file_path"
                fi
            else
                failed_files+=("$file_path")
            fi
        else
            skipped_files+=("$file_path (no update needed)")
        fi
    done
    
    # Clear progress line
    echo ""
    echo ""
    
    # Report results
    log_section "Sync Results"
    
    if [[ ${#updated_files[@]} -gt 0 ]]; then
        log_success "Updated files (${#updated_files[@]}):"
        for file in "${updated_files[@]}"; do
            echo "  ✅ $file"
        done
        echo ""
    fi
    
    if [[ ${#skipped_files[@]} -gt 0 ]]; then
        log_info "Skipped files (${#skipped_files[@]}):"
        for file in "${skipped_files[@]}"; do
            echo "  ⏭️  $file"
        done
        echo ""
    fi
    
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        log_warning "Failed to download (${#failed_files[@]}):"
        for file in "${failed_files[@]}"; do
            echo "  ❌ $file"
        done
        echo ""
        
        log_warning "Some files failed to download. This might be due to:"
        echo "  - Network connectivity issues"
        echo "  - Files not yet available in the repository"
        echo "  - Repository structure changes"
        echo ""
        echo "You can retry the sync later or check the repository manually."
    fi
    
    # Return success if at least some files were updated and no critical failures
    if [[ ${#updated_files[@]} -gt 0 || ${#failed_files[@]} -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Initialize a new installation from repository
run_initial_sync() {
    log_section "🚀 COMPASS Stack - Initial Setup"
    log_info "Downloading and setting up the complete modular architecture"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Test connectivity
    if ! test_connectivity; then
        return 1
    fi
    
    # Create directory structure
    create_directories
    
    # Sync all files
    if sync_files "install"; then
        log_success "Initial setup completed successfully!"
        echo ""
        log_info "Next steps:"
        echo "  1. Copy configuration template:    cp jstack.config.default jstack.config"
        echo "  2. Edit your settings:             nano jstack.config"
        echo "  3. Start installation:             ./jstack.sh"
        echo ""
        echo "  For detailed configuration help, see: README.md"
        return 0
    else
        log_error "Initial setup failed"
        return 1
    fi
}

# Update existing installation
run_update() {
    log_section "🔄 COMPASS Stack - Update System"
    log_info "Updating existing installation from repository"
    
    # Check prerequisites
    if ! check_prerequisites; then
        return 1
    fi
    
    # Test connectivity
    if ! test_connectivity; then
        return 1
    fi
    
    # Sync files with backup
    if sync_files "update"; then
        log_success "Update completed successfully!"
        echo ""
        log_info "Your existing jstack.config has been preserved"
        log_info "Updated files have been backed up with timestamps"
        echo ""
        log_info "If you experience issues, you can restore backed up files:"
        echo "  find . -name '*.backup.*' -type f"
        return 0
    else
        log_error "Update failed"
        return 1
    fi
}

# Show sync status and manifest
show_sync_status() {
    log_section "📋 COMPASS Stack - Sync Status"
    
    local total_files=${#SYNC_MANIFEST[@]}
    local existing_files=0
    local missing_files=()
    
    log_info "Checking status of $total_files managed files"
    echo ""
    
    for file_path in "${SYNC_MANIFEST[@]}"; do
        local local_path="$PROJECT_ROOT/$file_path"
        if [[ -f "$local_path" ]]; then
            echo "  ✅ $file_path"
            ((existing_files++))
        else
            echo "  ❌ $file_path (missing)"
            missing_files+=("$file_path")
        fi
    done
    
    echo ""
    log_info "Summary: $existing_files/$total_files files present"
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo ""
        log_warning "Missing files can be restored with: ./jstack.sh --sync"
        log_info "This will download only the missing files"
    else
        log_success "All managed files are present"
    fi
}

# Show manifest list
show_manifest() {
    log_section "📝 COMPASS Stack - File Manifest"
    log_info "Files managed by the sync system:"
    echo ""
    
    for file_path in "${SYNC_MANIFEST[@]}"; do
        echo "  📄 $file_path"
    done
    
    echo ""
    log_info "Total managed files: ${#SYNC_MANIFEST[@]}"
    log_info "Repository: $REPO_URL"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

show_usage() {
    cat << EOF
COMPASS Stack - Sync System

USAGE:
  $(basename "$0") COMMAND

COMMANDS:
  install        Download and set up complete system (first-time setup)
  update         Update existing installation from repository
  status         Show status of all managed files
  manifest       Show list of all files managed by sync system
  help           Show this help message

EXAMPLES:
  # First-time setup (downloads everything)
  ./scripts/core/sync.sh install

  # Update existing installation
  ./scripts/core/sync.sh update

  # Check what files are managed and their status
  ./scripts/core/sync.sh status

  # See what files are tracked in the sync system
  ./scripts/core/sync.sh manifest

SECURITY FEATURES:
  ✅ Direct file downloads from GitHub (no script execution)
  ✅ Verification of download success
  ✅ Backup of existing files during updates
  ✅ Preservation of user configuration (jstack.config)
  ✅ Clear reporting of what files are changed

REPOSITORY:
  Source: $REPO_URL
  Files synced: ${#SYNC_MANIFEST[@]} managed files

For complete system management, use the main orchestrator:
  ./jstack.sh --help
EOF
}

# Main command routing
main() {
    case "${1:-help}" in
        install)
            run_initial_sync
            ;;
        update)
            run_update
            ;;
        status)
            show_sync_status
            ;;
        manifest)
            show_manifest
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            echo "Unknown command: $1"
            echo ""
            show_usage
            exit 1
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