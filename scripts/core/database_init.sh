#!/bin/bash
# Database Initialization and Setup for COMPASS Stack
# Handles PostgreSQL database initialization, user creation, and N8N database setup

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🗄️ DATABASE INITIALIZATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Wait for PostgreSQL to be fully ready
wait_for_postgres_ready() {
    local timeout="${1:-120}"
    local interval="${2:-5}"
    local elapsed=0
    
    log_info "Waiting for PostgreSQL to be fully ready (timeout: ${timeout}s)"
    
    while [ $elapsed -lt $timeout ]; do
        # Check if container is running
        if ! docker ps --filter "name=supabase-db" --format '{{.Names}}' | grep -q "supabase-db"; then
            log_error "PostgreSQL container is not running"
            return 1
        fi
        
        # Check if PostgreSQL is accepting connections
        if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
            # Double-check with a simple query
            if docker exec supabase-db psql -U postgres -c "SELECT 1;" >/dev/null 2>&1; then
                log_success "PostgreSQL is fully ready and accepting connections"
                return 0
            fi
        fi
        
        if [[ $((elapsed % 15)) -eq 0 ]]; then
            log_info "Still waiting for PostgreSQL... (${elapsed}s elapsed)"
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "PostgreSQL failed to become ready within ${timeout}s"
    return 1
}

# Initialize Supabase database schema
initialize_supabase_schema() {
    log_section "Initializing Supabase Database Schema"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize Supabase database schema"
        return 0
    fi
    
    start_section_timer "Supabase Schema Init"
    
    # Wait for PostgreSQL to be ready
    if ! wait_for_postgres_ready; then
        log_error "Cannot initialize schema - PostgreSQL not ready"
        return 1
    fi
    
    # Create Supabase required extensions
    log_info "Installing required PostgreSQL extensions"
    
    local extensions=(
        "uuid-ossp"
        "pgcrypto"
        "pgjwt"
    )
    
    for ext in "${extensions[@]}"; do
        log_info "Installing extension: $ext"
        if docker exec supabase-db psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS \"$ext\";" >/dev/null 2>&1; then
            log_success "Extension $ext installed successfully"
        else
            log_warning "Failed to install extension $ext - may not be available"
        fi
    done
    
    # Create auth schema for Supabase Auth
    log_info "Creating auth schema"
    docker exec supabase-db psql -U postgres -c "CREATE SCHEMA IF NOT EXISTS auth;" >/dev/null 2>&1
    
    # Create storage schema for Supabase Storage
    log_info "Creating storage schema"
    docker exec supabase-db psql -U postgres -c "CREATE SCHEMA IF NOT EXISTS storage;" >/dev/null 2>&1
    
    # Create realtime schema
    log_info "Creating realtime schema"
    docker exec supabase-db psql -U postgres -c "CREATE SCHEMA IF NOT EXISTS _realtime;" >/dev/null 2>&1
    
    # Create graphql_public schema
    log_info "Creating graphql_public schema"
    docker exec supabase-db psql -U postgres -c "CREATE SCHEMA IF NOT EXISTS graphql_public;" >/dev/null 2>&1
    
    end_section_timer "Supabase Schema Init"
    log_success "Supabase database schema initialized"
    return 0
}

# Create N8N database and user
setup_n8n_database() {
    log_section "Setting up N8N Database"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup N8N database"
        return 0
    fi
    
    start_section_timer "N8N Database Setup"
    
    # Wait for PostgreSQL to be ready
    if ! wait_for_postgres_ready; then
        log_error "Cannot setup N8N database - PostgreSQL not ready"
        return 1
    fi
    
    # Get N8N database password from environment file if it exists
    local n8n_password=""
    local n8n_env_file="$BASE_DIR/services/n8n/.env"
    
    if [[ -f "$n8n_env_file" ]]; then
        n8n_password=$(grep "DB_POSTGRESDB_PASSWORD=" "$n8n_env_file" | cut -d'=' -f2 | tr -d '"')
    fi
    
    # Generate password if not found
    if [[ -z "$n8n_password" ]]; then
        n8n_password=$(generate_password)
        log_info "Generated new N8N database password"
    else
        log_info "Using existing N8N database password from configuration"
    fi
    
    # Create N8N database
    log_info "Creating N8N database"
    if docker exec supabase-db psql -U postgres -c "SELECT 1 FROM pg_database WHERE datname='n8n';" | grep -q 1; then
        log_info "N8N database already exists"
    else
        if docker exec supabase-db psql -U postgres -c "CREATE DATABASE n8n WITH ENCODING 'UTF8';" >/dev/null 2>&1; then
            log_success "N8N database created successfully"
        else
            log_error "Failed to create N8N database"
            return 1
        fi
    fi
    
    # Create N8N user
    log_info "Creating N8N database user"
    if docker exec supabase-db psql -U postgres -c "SELECT 1 FROM pg_roles WHERE rolname='n8n_user';" | grep -q 1; then
        log_info "N8N user already exists - updating password"
        docker exec supabase-db psql -U postgres -c "ALTER USER n8n_user WITH PASSWORD '$n8n_password';" >/dev/null 2>&1
    else
        if docker exec supabase-db psql -U postgres -c "CREATE USER n8n_user WITH PASSWORD '$n8n_password';" >/dev/null 2>&1; then
            log_success "N8N user created successfully"
        else
            log_error "Failed to create N8N user"
            return 1
        fi
    fi
    
    # Grant permissions to N8N user
    log_info "Granting permissions to N8N user"
    local grant_commands=(
        "GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;"
        "ALTER DATABASE n8n OWNER TO n8n_user;"
    )
    
    for cmd in "${grant_commands[@]}"; do
        if docker exec supabase-db psql -U postgres -c "$cmd" >/dev/null 2>&1; then
            log_success "Permission granted: $cmd"
        else
            log_warning "Failed to grant permission: $cmd"
        fi
    done
    
    # Test N8N database connection
    log_info "Testing N8N database connection"
    if docker exec supabase-db psql -U n8n_user -d n8n -c "SELECT version();" >/dev/null 2>&1; then
        log_success "N8N database connection test passed"
    else
        log_warning "N8N database connection test failed - check credentials"
    fi
    
    end_section_timer "N8N Database Setup"
    log_success "N8N database setup completed"
    return 0
}

# Setup database roles and permissions
setup_database_security() {
    log_section "Setting up Database Security and Roles"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup database security"
        return 0
    fi
    
    start_section_timer "Database Security"
    
    # Wait for PostgreSQL to be ready
    if ! wait_for_postgres_ready; then
        log_error "Cannot setup database security - PostgreSQL not ready"
        return 1
    fi
    
    # Create anon role for Supabase (public API access)
    log_info "Creating anon role for public API access"
    docker exec supabase-db psql -U postgres -c "CREATE ROLE IF NOT EXISTS anon NOLOGIN NOINHERIT;" >/dev/null 2>&1
    
    # Create authenticated role for authenticated users
    log_info "Creating authenticated role"
    docker exec supabase-db psql -U postgres -c "CREATE ROLE IF NOT EXISTS authenticated NOLOGIN NOINHERIT;" >/dev/null 2>&1
    
    # Create service_role for admin operations
    log_info "Creating service_role for admin operations"
    docker exec supabase-db psql -U postgres -c "CREATE ROLE IF NOT EXISTS service_role NOLOGIN NOINHERIT BYPASSRLS;" >/dev/null 2>&1
    
    # Grant basic permissions to roles
    log_info "Setting up role permissions"
    local role_permissions=(
        "GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;"
        "GRANT CREATE ON SCHEMA public TO anon, authenticated, service_role;"
        "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;"
        "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;"
        "GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;"
        "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;"
        "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;"
        "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;"
    )
    
    for permission in "${role_permissions[@]}"; do
        if docker exec supabase-db psql -U postgres -c "$permission" >/dev/null 2>&1; then
            log_success "Permission set: ${permission:0:50}..."
        else
            log_warning "Failed to set permission: ${permission:0:50}..."
        fi
    done
    
    end_section_timer "Database Security"
    log_success "Database security setup completed"
    return 0
}

# Initialize database with performance optimizations
setup_database_performance() {
    log_section "Setting up Database Performance Optimizations"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would setup database performance optimizations"
        return 0
    fi
    
    start_section_timer "Database Performance"
    
    # Wait for PostgreSQL to be ready
    if ! wait_for_postgres_ready; then
        log_error "Cannot setup performance optimizations - PostgreSQL not ready"
        return 1
    fi
    
    # Apply performance settings
    log_info "Applying PostgreSQL performance settings"
    
    local performance_settings=(
        "ALTER SYSTEM SET shared_buffers = '${POSTGRES_SHARED_BUFFERS}';"
        "ALTER SYSTEM SET effective_cache_size = '${POSTGRES_EFFECTIVE_CACHE_SIZE}';"
        "ALTER SYSTEM SET work_mem = '${POSTGRES_WORK_MEM}';"
        "ALTER SYSTEM SET maintenance_work_mem = '${POSTGRES_MAINTENANCE_WORK_MEM}';"
        "ALTER SYSTEM SET max_connections = ${POSTGRES_MAX_CONNECTIONS};"
        "ALTER SYSTEM SET random_page_cost = 1.1;"
        "ALTER SYSTEM SET effective_io_concurrency = 200;"
        "ALTER SYSTEM SET checkpoint_completion_target = 0.9;"
        "ALTER SYSTEM SET wal_buffers = '16MB';"
        "ALTER SYSTEM SET default_statistics_target = 100;"
    )
    
    for setting in "${performance_settings[@]}"; do
        if docker exec supabase-db psql -U postgres -c "$setting" >/dev/null 2>&1; then
            log_success "Performance setting applied: ${setting:0:40}..."
        else
            log_warning "Failed to apply setting: ${setting:0:40}..."
        fi
    done
    
    # Reload configuration
    log_info "Reloading PostgreSQL configuration"
    if docker exec supabase-db psql -U postgres -c "SELECT pg_reload_conf();" >/dev/null 2>&1; then
        log_success "PostgreSQL configuration reloaded"
    else
        log_warning "Failed to reload PostgreSQL configuration"
    fi
    
    end_section_timer "Database Performance"
    log_success "Database performance optimization completed"
    return 0
}

# Validate database setup
validate_database_setup() {
    log_section "Validating Database Setup"
    
    start_section_timer "Database Validation"
    
    local validation_failed=false
    
    # Test PostgreSQL connection
    log_info "Testing PostgreSQL connection"
    if docker exec supabase-db psql -U postgres -c "SELECT version();" >/dev/null 2>&1; then
        log_success "PostgreSQL connection: OK"
    else
        log_error "PostgreSQL connection: FAILED"
        validation_failed=true
    fi
    
    # Test N8N database
    log_info "Testing N8N database"
    if docker exec supabase-db psql -U postgres -d n8n -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "N8N database: OK"
    else
        log_error "N8N database: FAILED"
        validation_failed=true
    fi
    
    # Test N8N user permissions
    log_info "Testing N8N user permissions"
    if docker exec supabase-db psql -U n8n_user -d n8n -c "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY); DROP TABLE test_table;" >/dev/null 2>&1; then
        log_success "N8N user permissions: OK"
    else
        log_error "N8N user permissions: FAILED"
        validation_failed=true
    fi
    
    # Test Supabase schemas
    log_info "Testing Supabase schemas"
    local schemas=("auth" "storage" "_realtime" "graphql_public")
    for schema in "${schemas[@]}"; do
        if docker exec supabase-db psql -U postgres -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name='$schema';" | grep -q "$schema"; then
            log_success "Schema $schema: OK"
        else
            log_warning "Schema $schema: Missing"
        fi
    done
    
    # Test extensions
    log_info "Testing PostgreSQL extensions"
    local extensions=("uuid-ossp" "pgcrypto")
    for ext in "${extensions[@]}"; do
        if docker exec supabase-db psql -U postgres -c "SELECT 1 FROM pg_extension WHERE extname='$ext';" | grep -q 1; then
            log_success "Extension $ext: Installed"
        else
            log_warning "Extension $ext: Not installed"
        fi
    done
    
    # Show database statistics
    log_info "Database statistics:"
    local db_stats=$(docker exec supabase-db psql -U postgres -c "SELECT datname, numbackends, xact_commit, xact_rollback FROM pg_stat_database WHERE datname IN ('postgres', 'n8n');" 2>/dev/null || echo "Unable to retrieve stats")
    echo "$db_stats"
    
    end_section_timer "Database Validation"
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Database validation failed - some components are not working correctly"
        return 1
    else
        log_success "Database validation completed successfully"
        return 0
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 COMPLETE DATABASE INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

# Complete database initialization workflow
initialize_complete_database() {
    log_section "Complete Database Initialization Workflow"
    
    # Initialize timing
    init_timing_system
    
    # Execute initialization steps in sequence
    if initialize_supabase_schema && \
       setup_n8n_database && \
       setup_database_security && \
       setup_database_performance && \
       validate_database_setup; then
        
        log_success "Complete database initialization completed successfully"
        
        # Show final status
        log_info "Database initialization summary:"
        echo "  ✓ Supabase schemas created"
        echo "  ✓ N8N database and user configured"
        echo "  ✓ Security roles and permissions set"
        echo "  ✓ Performance optimizations applied"
        echo "  ✓ All components validated"
        
        return 0
    else
        log_error "Database initialization failed"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    case "${1:-complete}" in
        "complete"|"init")
            initialize_complete_database
            ;;
        "supabase")
            initialize_supabase_schema
            ;;
        "n8n")
            setup_n8n_database
            ;;
        "security")
            setup_database_security
            ;;
        "performance")
            setup_database_performance
            ;;
        "validate")
            validate_database_setup
            ;;
        "wait")
            wait_for_postgres_ready "$2"
            ;;
        *)
            echo "Usage: $0 [complete|supabase|n8n|security|performance|validate|wait]"
            echo ""
            echo "Commands:"
            echo "  complete      - Complete database initialization (default)"
            echo "  supabase      - Initialize Supabase database schema only"
            echo "  n8n           - Setup N8N database and user only"
            echo "  security      - Setup database security and roles only"
            echo "  performance   - Apply performance optimizations only"
            echo "  validate      - Validate database setup"
            echo "  wait [timeout] - Wait for PostgreSQL to be ready"
            echo ""
            echo "Examples:"
            echo "  $0                    # Complete initialization"
            echo "  $0 wait 60           # Wait up to 60s for PostgreSQL"
            echo "  $0 validate          # Check database setup"
            echo "  $0 n8n               # Setup N8N database only"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi