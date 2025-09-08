#!/bin/bash
# Backup and Restore System for COMPASS Stack
# Handles complete system backup and restore with encryption and compression

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔐 BACKUP ENCRYPTION AND SECURITY
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize backup encryption
init_backup_encryption() {
    local encryption_key_file="$BASE_DIR/config/backup.key"
    
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize backup encryption"
        if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
            log_info "[DRY-RUN] Would create config directory: $BASE_DIR/config"
            log_info "[DRY-RUN] Would generate encryption key: $encryption_key_file"
            log_info "[DRY-RUN] Would set permissions 600 on encryption key"
        else
            log_info "[DRY-RUN] Backup encryption disabled"
        fi
        return 0
    fi

    if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
        log_info "Initializing backup encryption"
        
        # Create secure config directory
        execute_cmd "sudo -u $SERVICE_USER mkdir -p $BASE_DIR/config" "Create config directory"
        
        # Generate encryption key if it doesn't exist
        if [[ ! -f "$encryption_key_file" ]]; then
            log_info "Generating new backup encryption key"
            execute_cmd "sudo -u $SERVICE_USER openssl rand -base64 32 > $encryption_key_file" "Generate encryption key"
            safe_chmod "600" "$encryption_key_file"
        fi
        
        log_success "Backup encryption initialized"
        return 0
    else
        log_info "Backup encryption disabled"
        return 0
    fi
}

# Encrypt backup file
encrypt_backup() {
    local input_file="$1"
    local output_file="$2"
    local encryption_key_file="$BASE_DIR/config/backup.key"
    
    if [[ "$BACKUP_ENCRYPTION" == "true" ]] && [[ -f "$encryption_key_file" ]]; then
        log_info "Encrypting backup: $(basename "$input_file")"
        
        if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$input_file" -out "$output_file" -pass file:"$encryption_key_file"; then
            rm -f "$input_file"
            log_success "Backup encrypted successfully"
            return 0
        else
            log_error "Backup encryption failed"
            return 1
        fi
    else
        # No encryption - just move file
        mv "$input_file" "$output_file"
        return 0
    fi
}

# Decrypt backup file
decrypt_backup() {
    local input_file="$1"
    local output_file="$2"
    local encryption_key_file="$BASE_DIR/config/backup.key"
    
    if [[ "$BACKUP_ENCRYPTION" == "true" ]] && [[ -f "$encryption_key_file" ]]; then
        log_info "Decrypting backup: $(basename "$input_file")"
        
        if openssl enc -aes-256-cbc -d -pbkdf2 -in "$input_file" -out "$output_file" -pass file:"$encryption_key_file"; then
            log_success "Backup decrypted successfully"
            return 0
        else
            log_error "Backup decryption failed"
            return 1
        fi
    else
        # No decryption - just copy file
        cp "$input_file" "$output_file"
        return 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🗄️ DATABASE BACKUP AND RESTORE
# ═══════════════════════════════════════════════════════════════════════════════

# Create database backup
backup_databases() {
    log_section "Creating Database Backup"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would backup databases"
        return 0
    fi
    
    start_section_timer "Database Backup"
    
    local backup_dir="$1"
    local db_backup_dir="$backup_dir/databases"
    
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $db_backup_dir" "Create database backup directory"
    
    # Check if containers are running
    if ! docker ps --format '{{.Names}}' | grep -q "supabase-db"; then
        log_error "Supabase database container is not running"
        return 1
    fi
    
    # Backup main PostgreSQL database
    log_info "Backing up main PostgreSQL database"
    local main_db_backup="$db_backup_dir/postgres_main.sql"
    
    if docker_cmd "docker exec supabase-db pg_dumpall -U postgres > $main_db_backup" "Backup PostgreSQL main database"; then
        log_success "Main database backup completed"
    else
        log_error "Main database backup failed"
        return 1
    fi
    
    # Backup N8N database if it exists
    if docker_cmd "docker exec supabase-db psql -U postgres -lqt" "Check N8N database" | cut -d \| -f 1 | grep -qw n8n; then
        log_info "Backing up N8N database"
        local n8n_db_backup="$db_backup_dir/n8n.sql"
        
        if docker_cmd "docker exec supabase-db pg_dump -U postgres n8n > $n8n_db_backup" "Backup N8N database"; then
            log_success "N8N database backup completed"
        else
            log_warning "N8N database backup failed"
        fi
    fi
    
    # Set ownership
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$db_backup_dir" "Set database backup ownership"
    
    end_section_timer "Database Backup"
    log_success "Database backup completed"
    return 0
}

# Restore database backup
restore_databases() {
    log_section "Restoring Database Backup"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore databases"
        return 0
    fi
    
    start_section_timer "Database Restore"
    
    local backup_dir="$1"
    local db_backup_dir="$backup_dir/databases"
    
    if [[ ! -d "$db_backup_dir" ]]; then
        log_error "Database backup directory not found: $db_backup_dir"
        return 1
    fi
    
    # Check if containers are running
    if ! docker ps --format '{{.Names}}' | grep -q "supabase-db"; then
        log_error "Supabase database container is not running"
        log_info "Starting database container for restore"
        
        local supabase_dir="$BASE_DIR/services/supabase"
        if [[ -f "$supabase_dir/docker-compose.yml" ]]; then
            docker_cmd "cd $supabase_dir && docker-compose up -d supabase-db" "Start database container"
            wait_for_service_health "supabase-db" 120 10
        else
            log_error "Supabase configuration not found"
            return 1
        fi
    fi
    
    # Restore main PostgreSQL database
    local main_db_backup="$db_backup_dir/postgres_main.sql"
    if [[ -f "$main_db_backup" ]]; then
        log_info "Restoring main PostgreSQL database"
        
        # Stop all services that depend on database
        log_info "Stopping dependent services for database restore"
        docker_cmd "docker stop supabase-auth supabase-rest supabase-realtime supabase-storage supabase-studio supabase-meta supabase-kong n8n" "Stop dependent services" || true
        
        # Clear existing data (WARNING: This is destructive)
        log_warning "This will completely replace all existing database data!"
        sleep 5
        
        if docker_cmd "docker exec -i supabase-db psql -U postgres < $main_db_backup" "Restore main database"; then
            log_success "Main database restore completed"
        else
            log_error "Main database restore failed"
            return 1
        fi
    else
        log_warning "Main database backup file not found: $main_db_backup"
    fi
    
    # Restore N8N database if backup exists
    local n8n_db_backup="$db_backup_dir/n8n.sql"
    if [[ -f "$n8n_db_backup" ]]; then
        log_info "Restoring N8N database"
        
        # Create N8N database if it doesn't exist
        docker_cmd "docker exec supabase-db psql -U postgres -c \"CREATE DATABASE n8n;\"" "Create N8N database" || true
        
        if docker_cmd "docker exec -i supabase-db psql -U postgres -d n8n < $n8n_db_backup" "Restore N8N database"; then
            log_success "N8N database restore completed"
        else
            log_warning "N8N database restore failed"
        fi
    fi
    
    # Restart all services after database restore
    log_info "Restarting all services after database restore"
    local supabase_dir="$BASE_DIR/services/supabase"
    local n8n_dir="$BASE_DIR/services/n8n"
    
    if [[ -f "$supabase_dir/docker-compose.yml" ]]; then
        docker_cmd "cd $supabase_dir && docker-compose up -d" "Restart Supabase services"
        
        # Wait for critical services
        wait_for_service_health "supabase-db" 120 10
        wait_for_service_health "supabase-auth" 60 5
        wait_for_service_health "supabase-rest" 60 5
    fi
    
    if [[ -f "$n8n_dir/docker-compose.yml" ]]; then
        docker_cmd "cd $n8n_dir && docker-compose up -d" "Restart N8N service"
        wait_for_service_health "n8n" 60 5
    fi
    
    end_section_timer "Database Restore"
    log_success "Database restore completed"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📁 CONFIGURATION AND VOLUME BACKUP
# ═══════════════════════════════════════════════════════════════════════════════

# Backup configuration files and Docker volumes
backup_configurations_and_volumes() {
    log_section "Backing up Configurations and Volumes"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would backup configurations and volumes"
        return 0
    fi
    
    start_section_timer "Config and Volume Backup"
    
    local backup_dir="$1"
    local config_backup_dir="$backup_dir/config"
    local volume_backup_dir="$backup_dir/volumes"
    
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $config_backup_dir $volume_backup_dir" "Create backup directories"
    
    # Backup configuration files
    log_info "Backing up configuration files"
    
    # Copy main project configuration
    if [[ -f "$PROJECT_ROOT/jstack.config" ]]; then
        safe_execute "cp $PROJECT_ROOT/jstack.config $config_backup_dir/" "Copy main config"
    fi
    
    # Copy service configurations
    if [[ -d "$BASE_DIR/services" ]]; then
        safe_execute "cp -r $BASE_DIR/services $config_backup_dir/" "Copy service configs"
        
        # Remove sensitive data from copied configs (keep structure but mask secrets)
        find "$config_backup_dir/services" -name "*.env" -type f -exec sed -i 's/=.*/=***MASKED***/' {} \;
        log_info "Masked sensitive data in configuration backup"
    fi
    
    # Backup SSL certificates
    if [[ -d "$BASE_DIR/services/nginx/ssl" ]]; then
        safe_execute "cp -r $BASE_DIR/services/nginx/ssl $config_backup_dir/" "Copy SSL certificates"
    fi
    
    # Backup custom scripts and tools
    if [[ -d "$BASE_DIR/scripts" ]]; then
        safe_execute "cp -r $BASE_DIR/scripts $config_backup_dir/" "Copy custom scripts"
    fi
    
    # Backup Docker volumes (data only)
    log_info "Backing up Docker volumes"
    
    # Get list of COMPASS volumes
    local volumes=$(docker volume ls --filter "name=supabase" --filter "name=n8n" --format "{{.Name}}" 2>/dev/null || true)
    
    if [[ -n "$volumes" ]]; then
        for volume in $volumes; do
            log_info "Backing up Docker volume: $volume"
            local volume_backup_file="$volume_backup_dir/${volume}.tar"
            
            # Create volume backup using a temporary container
            if docker run --rm -v "$volume:/data" -v "$volume_backup_dir:/backup" alpine:latest tar -czf "/backup/${volume}.tar.gz" -C /data .; then
                log_success "Volume backup completed: $volume"
            else
                log_warning "Volume backup failed: $volume"
            fi
        done
    else
        log_info "No Docker volumes found to backup"
    fi
    
    # Set ownership
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$config_backup_dir" "Set config backup ownership"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$volume_backup_dir" "Set volume backup ownership"
    
    end_section_timer "Config and Volume Backup"
    log_success "Configuration and volume backup completed"
    return 0
}

# Restore configuration files and Docker volumes
restore_configurations_and_volumes() {
    log_section "Restoring Configurations and Volumes"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore configurations and volumes"
        return 0
    fi
    
    start_section_timer "Config and Volume Restore"
    
    local backup_dir="$1"
    local config_backup_dir="$backup_dir/config"
    local volume_backup_dir="$backup_dir/volumes"
    
    # Restore configuration files
    if [[ -d "$config_backup_dir" ]]; then
        log_info "Restoring configuration files"
        
        # Restore service configurations
        if [[ -d "$config_backup_dir/services" ]]; then
            log_warning "Configuration restore will overwrite existing service configs"
            safe_execute "cp -r $config_backup_dir/services/* $BASE_DIR/services/" "Restore service configs" || true
            
            # Note: Environment files need to be recreated with actual secrets, not masked ones
            log_warning "Environment files contain masked secrets - you may need to regenerate them"
        fi
        
        # Restore SSL certificates
        if [[ -d "$config_backup_dir/ssl" ]]; then
            execute_cmd "sudo -u $SERVICE_USER mkdir -p $BASE_DIR/services/nginx/ssl" "Create SSL directory"
            safe_execute "cp -r $config_backup_dir/ssl/* $BASE_DIR/services/nginx/ssl/" "Restore SSL certificates" || true
        fi
        
        # Restore custom scripts
        if [[ -d "$config_backup_dir/scripts" ]]; then
            execute_cmd "sudo -u $SERVICE_USER mkdir -p $BASE_DIR/scripts" "Create scripts directory"
            safe_execute "cp -r $config_backup_dir/scripts/* $BASE_DIR/scripts/" "Restore custom scripts" || true
        fi
        
        log_success "Configuration restore completed"
    else
        log_warning "Configuration backup directory not found: $config_backup_dir"
    fi
    
    # Restore Docker volumes
    if [[ -d "$volume_backup_dir" ]]; then
        log_info "Restoring Docker volumes"
        
        # Stop all services before volume restore
        log_info "Stopping all services for volume restore"
        docker_cmd "docker-compose -f $BASE_DIR/services/supabase/docker-compose.yml down" "Stop Supabase services" || true
        docker_cmd "docker-compose -f $BASE_DIR/services/n8n/docker-compose.yml down" "Stop N8N services" || true
        docker_cmd "docker-compose -f $BASE_DIR/services/nginx/docker-compose.yml down" "Stop NGINX services" || true
        
        # Restore each volume
        for volume_backup in "$volume_backup_dir"/*.tar.gz; do
            if [[ -f "$volume_backup" ]]; then
                local volume_name=$(basename "$volume_backup" .tar.gz)
                log_info "Restoring Docker volume: $volume_name"
                
                # Create volume if it doesn't exist
                docker volume create "$volume_name" >/dev/null 2>&1 || true
                
                # Restore volume data
                if docker run --rm -v "$volume_name:/data" -v "$volume_backup_dir:/backup" alpine:latest tar -xzf "/backup/${volume_name}.tar.gz" -C /data; then
                    log_success "Volume restore completed: $volume_name"
                else
                    log_error "Volume restore failed: $volume_name"
                fi
            fi
        done
        
        log_success "Docker volume restore completed"
    else
        log_warning "Volume backup directory not found: $volume_backup_dir"
    fi
    
    end_section_timer "Config and Volume Restore"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📦 COMPLETE SYSTEM BACKUP
# ═══════════════════════════════════════════════════════════════════════════════

# Create complete system backup
create_system_backup() {
    local backup_name="${1:-$(date '+%Y%m%d_%H%M%S')}"
    
    log_section "Creating Complete System Backup: $backup_name"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would create system backup: $backup_name"
        log_info "[DRY-RUN] Backup components would include:"
        log_info "[DRY-RUN]   • Database dumps (PostgreSQL)"
        log_info "[DRY-RUN]   • Configuration files (jstack.config, SSL certs)"
        log_info "[DRY-RUN]   • Docker volumes (persistent data)"
        log_info "[DRY-RUN]   • Service logs and system state"
        log_info "[DRY-RUN] Final backup file: $BASE_DIR/backups/backup_${backup_name}.tar.gz"
        return 0
    fi
    
    # Initialize timing and encryption
    init_timing_system
    init_backup_encryption
    
    start_section_timer "Complete System Backup"
    
    # Create backup directories
    local backup_root="$BASE_DIR/backups"
    local backup_temp_dir="$backup_root/temp_backup_$$"
    local backup_final_file="$backup_root/backup_${backup_name}.tar.gz"
    
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $backup_root $backup_temp_dir" "Create backup directories"
    
    # Create backup manifest (dry-run safe)
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$backup_temp_dir/backup_manifest.json" << EOF
{
  "backup_name": "$backup_name",
  "timestamp": "$(date -Iseconds)",
  "system_info": {
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "domain": "$DOMAIN",
    "jarvis_version": "$(cat $PROJECT_ROOT/VERSION 2>/dev/null || echo 'unknown')"
  },
  "backup_components": {
    "databases": true,
    "configurations": true,
    "volumes": true,
    "encryption": $([[ "$BACKUP_ENCRYPTION" == "true" ]] && echo "true" || echo "false")
  }
}
EOF
    else
        log_info "Would create backup manifest at: $backup_temp_dir/backup_manifest.json"
    fi
    
    # Perform backup components
    if backup_databases "$backup_temp_dir" && \
       backup_configurations_and_volumes "$backup_temp_dir"; then
        
        log_info "Creating compressed backup archive"
        
        # Create compressed archive
        local compression_level="${BACKUP_COMPRESSION_LEVEL:-6}"
        local temp_archive="$backup_temp_dir.tar.gz"
        
        if tar -czf "$temp_archive" -C "$backup_root" "$(basename "$backup_temp_dir")"; then
            log_success "Backup archive created successfully"
            
            # Encrypt if enabled
            if [[ "$BACKUP_ENCRYPTION" == "true" ]]; then
                local encrypted_file="$backup_final_file.enc"
                if encrypt_backup "$temp_archive" "$encrypted_file"; then
                    backup_final_file="$encrypted_file"
                else
                    log_error "Backup encryption failed"
                    return 1
                fi
            else
                mv "$temp_archive" "$backup_final_file"
            fi
            
            # Set proper ownership and permissions
            safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$backup_final_file" "Set backup ownership"
            safe_chmod "600" "$backup_final_file" "Secure backup file"
            
            # Clean up temporary directory
            rm -rf "$backup_temp_dir"
            
            # Get backup size
            local backup_size=$(du -h "$backup_final_file" | cut -f1)
            
            log_success "System backup completed successfully"
            log_info "Backup file: $backup_final_file"
            log_info "Backup size: $backup_size"
            
            # Clean up old backups
            cleanup_old_backups
            
        else
            log_error "Failed to create backup archive"
            rm -rf "$backup_temp_dir"
            return 1
        fi
        
    else
        log_error "Backup component creation failed"
        rm -rf "$backup_temp_dir"
        return 1
    fi
    
    end_section_timer "Complete System Backup"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 SYSTEM RESTORE
# ═══════════════════════════════════════════════════════════════════════════════

# Restore complete system from backup
restore_system_backup() {
    local backup_file="$1"
    
    log_section "Restoring Complete System from Backup"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would restore system from: $backup_file"
        return 0
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    start_section_timer "Complete System Restore"
    
    # Create temporary restore directory
    local restore_temp_dir="$BASE_DIR/backups/temp_restore_$$"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $restore_temp_dir" "Create restore directory"
    
    # Decrypt if needed
    local working_backup_file="$backup_file"
    if [[ "$backup_file" =~ \.enc$ ]]; then
        log_info "Decrypting backup file"
        local decrypted_file="$restore_temp_dir/backup.tar.gz"
        
        if decrypt_backup "$backup_file" "$decrypted_file"; then
            working_backup_file="$decrypted_file"
        else
            log_error "Failed to decrypt backup file"
            rm -rf "$restore_temp_dir"
            return 1
        fi
    fi
    
    # Extract backup archive
    log_info "Extracting backup archive"
    if tar -xzf "$working_backup_file" -C "$restore_temp_dir"; then
        log_success "Backup archive extracted successfully"
        
        # Find the backup content directory
        local backup_content_dir=$(find "$restore_temp_dir" -name "temp_backup_*" -type d | head -n1)
        
        if [[ -z "$backup_content_dir" ]]; then
            log_error "Could not find backup content in archive"
            rm -rf "$restore_temp_dir"
            return 1
        fi
        
        # Check backup manifest
        local manifest_file="$backup_content_dir/backup_manifest.json"
        if [[ -f "$manifest_file" ]]; then
            log_info "Backup manifest found - validating backup"
            local backup_timestamp=$(grep '"timestamp"' "$manifest_file" | cut -d'"' -f4)
            local backup_domain=$(grep '"domain"' "$manifest_file" | cut -d'"' -f4)
            
            log_info "Backup created: $backup_timestamp"
            log_info "Original domain: $backup_domain"
            
            if [[ "$backup_domain" != "$DOMAIN" ]]; then
                log_warning "Backup domain ($backup_domain) differs from current domain ($DOMAIN)"
                log_warning "You may need to reconfigure domain-specific settings after restore"
            fi
        else
            log_warning "Backup manifest not found - proceeding with restore"
        fi
        
        # Perform restore operations
        if restore_databases "$backup_content_dir" && \
           restore_configurations_and_volumes "$backup_content_dir"; then
            
            log_success "System restore completed successfully"
            
            # Clean up
            rm -rf "$restore_temp_dir"
            
            log_info "System restore completed - you may need to restart services"
            log_info "Run: $PROJECT_ROOT/jstack.sh to restart all services"
            
        else
            log_error "System restore failed"
            rm -rf "$restore_temp_dir"
            return 1
        fi
        
    else
        log_error "Failed to extract backup archive"
        rm -rf "$restore_temp_dir"
        return 1
    fi
    
    end_section_timer "Complete System Restore"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🧹 BACKUP MAINTENANCE
# ═══════════════════════════════════════════════════════════════════════════════

# List available backups
list_available_backups() {
    log_section "Available System Backups"
    
    local backup_root="$BASE_DIR/backups"
    
    if [[ -d "$backup_root" ]]; then
        local backup_files=("$backup_root"/backup_*.tar.gz*)
        
        if [[ ${#backup_files[@]} -gt 0 && -f "${backup_files[0]}" ]]; then
            echo "Found backups in $backup_root:"
            echo ""
            printf "%-25s %-10s %-20s %s\n" "BACKUP NAME" "SIZE" "DATE" "ENCRYPTED"
            printf "%-25s %-10s %-20s %s\n" "----------" "----" "----" "---------"
            
            for backup_file in "${backup_files[@]}"; do
                if [[ -f "$backup_file" ]]; then
                    local backup_name=$(basename "$backup_file")
                    local backup_size=$(du -h "$backup_file" | cut -f1)
                    local backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
                    local encrypted="No"
                    
                    if [[ "$backup_file" =~ \.enc$ ]]; then
                        encrypted="Yes"
                    fi
                    
                    printf "%-25s %-10s %-20s %s\n" "$backup_name" "$backup_size" "$backup_date" "$encrypted"
                fi
            done
            echo ""
        else
            echo "No backups found in $backup_root"
        fi
    else
        echo "Backup directory does not exist: $backup_root"
    fi
}

# Clean up old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups"
    
    local backup_root="$BASE_DIR/backups"
    local retention_days="$BACKUP_RETENTION_DAYS"
    
    if [[ -d "$backup_root" ]] && [[ "$retention_days" =~ ^[0-9]+$ ]] && [[ $retention_days -gt 0 ]]; then
        # Find and remove backup files older than retention period
        local old_backups=$(find "$backup_root" -name "backup_*.tar.gz*" -type f -mtime +$retention_days 2>/dev/null || true)
        
        if [[ -n "$old_backups" ]]; then
            echo "$old_backups" | while read -r old_backup; do
                if [[ -f "$old_backup" ]]; then
                    log_info "Removing old backup: $(basename "$old_backup")"
                    rm -f "$old_backup"
                fi
            done
            
            log_success "Old backup cleanup completed"
        else
            log_info "No old backups to clean up"
        fi
    else
        log_info "Backup cleanup skipped (invalid retention days: $retention_days)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Interactive backup selection
interactive_restore_selection() {
    local backup_root="$BASE_DIR/backups"
    local backup_files=("$backup_root"/backup_*.tar.gz*)
    
    if [[ ${#backup_files[@]} -eq 0 || ! -f "${backup_files[0]}" ]]; then
        echo "No backup files found for interactive selection"
        return 1
    fi
    
    echo "Available backups for restore:"
    echo ""
    
    local i=1
    for backup_file in "${backup_files[@]}"; do
        if [[ -f "$backup_file" ]]; then
            local backup_name=$(basename "$backup_file")
            local backup_size=$(du -h "$backup_file" | cut -f1)
            local backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            
            echo "$i) $backup_name ($backup_size, $backup_date)"
            ((i++))
        fi
    done
    
    echo ""
    echo -n "Select backup to restore (1-$((i-1))) or 'c' to cancel: "
    read -r selection
    
    if [[ "$selection" == "c" ]] || [[ "$selection" == "C" ]]; then
        echo "Restore cancelled"
        return 1
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le $((i-1)) ]]; then
        local selected_backup="${backup_files[$((selection-1))]}"
        echo "Selected backup: $(basename "$selected_backup")"
        echo ""
        
        echo "WARNING: This will completely replace your current system with the backup data."
        echo "This action cannot be undone. Are you sure? (y/N)"
        read -r confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            restore_system_backup "$selected_backup"
        else
            echo "Restore cancelled"
            return 1
        fi
    else
        echo "Invalid selection"
        return 1
    fi
}

# Main function for command routing
main() {
    case "${1:-create}" in
        "create"|"backup")
            create_system_backup "$2"
            ;;
        "restore")
            if [[ -n "$2" ]]; then
                restore_system_backup "$2"
            else
                interactive_restore_selection
            fi
            ;;
        "list")
            list_available_backups
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        *)
            echo "Usage: $0 [create|restore|list|cleanup] [backup_name|backup_file]"
            echo ""
            echo "Commands:"
            echo "  create [name]   - Create system backup (optional custom name)"
            echo "  restore [file]  - Restore from backup (interactive if no file specified)"
            echo "  list           - List all available backups"
            echo "  cleanup        - Remove old backups based on retention policy"
            echo ""
            echo "Examples:"
            echo "  $0 create                    # Create timestamped backup"
            echo "  $0 create pre-upgrade        # Create named backup"
            echo "  $0 restore                   # Interactive restore selection"
            echo "  $0 restore backup_file.tar.gz # Restore specific backup"
            echo "  $0 list                      # Show all backups"
            echo "  $0 cleanup                   # Clean up old backups"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi