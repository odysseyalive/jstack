#!/bin/bash
# Configuration management for JStack
# Single source of truth for configuration loading

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

# Load configuration with proper precedence
load_config() {
    # First, check if user config exists
    if [[ ! -f "${PROJECT_ROOT}/jstack.config" ]]; then
        echo "ERROR: Configuration file not found: ${PROJECT_ROOT}/jstack.config"
        echo ""
        echo "To set up your configuration:"
        echo "  1. Copy the default config:    cp jstack.config.default jstack.config"
        echo "  2. Edit your settings:        nano jstack.config"  
        echo "  3. See documentation:         README.md"
        echo ""
        echo "You must customize DOMAIN and EMAIL in jstack.config before running."
        exit 1
    fi
    
    # Load defaults first
    if [[ -f "${PROJECT_ROOT}/jstack.config.default" ]]; then
        source "${PROJECT_ROOT}/jstack.config.default"
    else
        echo "ERROR: Default configuration file not found: ${PROJECT_ROOT}/jstack.config.default"
        exit 1
    fi
    
    # Override with user configuration
    source "${PROJECT_ROOT}/jstack.config"
    
    # Validate required configuration
    validate_required_config
}

# Validate that required configuration variables are set
# Validate that required configuration variables are set
validate_required_config() {
    # Allow placeholder values in development mode
    if [[ "${ENABLE_DEVELOPMENT_MODE:-false}" == "true" ]]; then
        echo "[DEVELOPMENT] Using development mode - placeholder values allowed"
        echo "[DEVELOPMENT] DOMAIN: ${DOMAIN}, EMAIL: ${EMAIL}"
        return 0
    fi
    
    local required_vars=("DOMAIN" "EMAIL")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]] || [[ "${!var}" == "example.com" ]] || [[ "${!var}" == "your-domain.com" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "ERROR: Required configuration variables not properly set in jstack.config:"
        printf "  %s\n" "${missing_vars[@]}"
        echo ""
        echo "Please edit jstack.config and set these variables to your actual values"
        echo "See README.md for configuration details"
        exit 1
    fi
}

# Export configuration for subprocesses
export_config() {
    # Export all configuration variables so they're available to modules
    export DOMAIN EMAIL COUNTRY_CODE STATE_NAME CITY_NAME ORGANIZATION
    export SUPABASE_SUBDOMAIN STUDIO_SUBDOMAIN N8N_SUBDOMAIN
    export DEPLOYMENT_ENVIRONMENT ENABLE_INTERNAL_SSL ENABLE_DEVELOPMENT_MODE
    export SERVICE_USER SERVICE_GROUP SERVICE_SHELL
    export BASE_DIR BACKUP_RETENTION_DAYS LOG_RETENTION_DAYS CONFIG_BACKUP_RETENTION
    export JARVIS_NETWORK PUBLIC_TIER PRIVATE_TIER
    export SUPABASE_API_PORT SUPABASE_STUDIO_PORT N8N_PORT NEXTJS_PORT POSTGRES_PORT
    export POSTGRES_MEMORY_LIMIT POSTGRES_CPU_LIMIT POSTGRES_SHARED_BUFFERS
    export POSTGRES_EFFECTIVE_CACHE_SIZE POSTGRES_WORK_MEM POSTGRES_MAINTENANCE_WORK_MEM POSTGRES_MAX_CONNECTIONS
    export N8N_MEMORY_LIMIT N8N_CPU_LIMIT N8N_EXECUTION_TIMEOUT N8N_MAX_EXECUTION_HISTORY N8N_TIMEZONE
    export NGINX_MEMORY_LIMIT NGINX_CPU_LIMIT NGINX_WORKER_PROCESSES NGINX_WORKER_CONNECTIONS
    export APPARMOR_ENABLED CONTAINER_USER_NAMESPACES CONTAINER_NO_NEW_PRIVS CONTAINER_READ_ONLY_ROOT UFW_ENABLED
    export BACKUP_SCHEDULE BACKUP_ENCRYPTION BACKUP_COMPRESSION_LEVEL DATABASE_BACKUP_RETENTION VOLUME_BACKUP_RETENTION
    export ENABLE_ALERTING ALERT_EMAIL SLACK_WEBHOOK
    export UPDATE_ROLLBACK_ON_FAILURE PRE_UPDATE_BACKUP IMAGE_CLEANUP_RETENTION
    export SUPABASE_DB_NAME SUPABASE_AUTH_SITE_URL
    export NGINX_CLIENT_MAX_BODY_SIZE NGINX_RATE_LIMIT_API NGINX_RATE_LIMIT_GENERAL NGINX_RATE_LIMIT_WEBHOOKS
    export NGINX_KEEPALIVE_TIMEOUT NGINX_GZIP_COMPRESSION
    export CONTAINER_LOG_MAX_SIZE CONTAINER_LOG_MAX_FILES AUDIT_LOGGING
    export ENABLE_DEBUG_LOGS DRY_RUN
}

# Main configuration loading function
main() {
    load_config
    export_config
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi