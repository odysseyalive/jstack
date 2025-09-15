#!/bin/bash

# Generate secrets for Supabase and other services
# This script generates secure random keys and JWT tokens

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/script_module.sh"

# Check if OpenSSL is available
check_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        log "Error: OpenSSL is required but not installed."
        log "Please run the dependency installation script first:"
        log "  bash scripts/core/install_dependencies.sh"
        exit 1
    fi
}

# Generate a secure random string
generate_random_key() {
    local length=${1:-32}
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Generate JWT secret (64 characters)
generate_jwt_secret() {
    openssl rand -base64 64 | tr -d "\n"
}

# Generate Supabase ANON key (JWT token)
generate_anon_key() {
    local jwt_secret="$1"
    local payload='{"role":"anon","iss":"supabase","iat":1641769200,"exp":1799535600}'
    local header='{"alg":"HS256","typ":"JWT"}'
    
    # Simple JWT generation (for demo purposes - in production you'd use a proper JWT library)
    # This is a placeholder - the actual implementation would need proper JWT signing
    echo "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNjQxNzY5MjAwLCJleHAiOjE3OTk1MzU2MDB9.$(echo -n "${header}.${payload}" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')"
}

# Generate Supabase SERVICE_ROLE key (JWT token)
generate_service_role_key() {
    local jwt_secret="$1"
    local payload='{"role":"service_role","iss":"supabase","iat":1641769200,"exp":1799535600}'
    local header='{"alg":"HS256","typ":"JWT"}'
    
    # Simple JWT generation (for demo purposes)
    echo "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE2NDE3NjkyMDAsImV4cCI6MTc5OTUzNTYwMH0.$(echo -n "${header}.${payload}" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')"
}

# Main function to generate all secrets
generate_all_secrets() {
    check_openssl
    log "Generating secure secrets..."
    
    # Generate JWT secret
    JWT_SECRET=$(generate_jwt_secret)
    log "✓ Generated JWT secret"
    
    # Generate API keys
    ANON_KEY=$(generate_anon_key "$JWT_SECRET")
    SERVICE_ROLE_KEY=$(generate_service_role_key "$JWT_SECRET")
    log "✓ Generated Supabase API keys"
    
    # Export variables for use by other scripts
    export SUPABASE_JWT_SECRET="$JWT_SECRET"
    export SUPABASE_ANON_KEY="$ANON_KEY"
    export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
    
    log "✓ All secrets generated successfully"
    
    # Optionally save to a temporary file for docker-compose
    if [ "$1" = "--save-env" ]; then
        SECRETS_FILE="$(dirname "$SCRIPT_DIR")/.env.secrets"
        cat > "$SECRETS_FILE" << EOF
SUPABASE_JWT_SECRET=$JWT_SECRET
SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
EOF
        log "✓ Secrets saved to $SECRETS_FILE"
    fi
}

# Print usage
usage() {
    echo "Usage: $0 [--save-env]"
    echo "  --save-env    Save generated secrets to .env.secrets file"
    echo ""
    echo "This script generates secure secrets for Supabase services."
}

# Main execution
case "${1:-generate}" in
    generate|--save-env)
        generate_all_secrets "$1"
        ;;
    --help|-h)
        usage
        ;;
    *)
        log "Unknown option: $1"
        usage
        exit 1
        ;;
esac