#!/bin/bash

# Generate secrets for Supabase and other services
# This script generates secure random keys and JWT tokens

set -e

# Basic logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

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
    # Pre-encoded base64 header and payload (standard JWT format)
    local header_payload="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNjQxNzY5MjAwLCJleHAiOjE3OTk1MzU2MDB9"

    # Generate HMAC-SHA256 signature of the header.payload
    local signature=$(echo -n "$header_payload" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')

    echo "${header_payload}.${signature}"
}

# Generate Supabase SERVICE_ROLE key (JWT token)
generate_service_role_key() {
    local jwt_secret="$1"
    # Pre-encoded base64 header and payload (standard JWT format)
    local header_payload="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE2NDE3NjkyMDAsImV4cCI6MTc5OTUzNTYwMH0"

    # Generate HMAC-SHA256 signature of the header.payload
    local signature=$(echo -n "$header_payload" | openssl dgst -sha256 -hmac "$jwt_secret" -binary | base64 | tr -d '\n' | tr '+/' '-_' | tr -d '=')

    echo "${header_payload}.${signature}"
}

# Main function to generate all secrets
generate_all_secrets() {
    check_openssl
    log "Generating secure secrets..."
    
    # Generate JWT secret
    JWT_SECRET=$(generate_jwt_secret)
    log "✓ Generated JWT secret"
    
    # Generate database password
    SUPABASE_PASSWORD=$(generate_random_key 24)
    log "✓ Generated database password"
    
    # Generate API keys
    ANON_KEY=$(generate_anon_key "$JWT_SECRET")
    SERVICE_ROLE_KEY=$(generate_service_role_key "$JWT_SECRET")
    log "✓ Generated Supabase API keys"
    
    # Export variables for use by other scripts
    export SUPABASE_PASSWORD="$SUPABASE_PASSWORD"
    export SUPABASE_JWT_SECRET="$JWT_SECRET"
    export SUPABASE_ANON_KEY="$ANON_KEY"
    export SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"
    
    log "✓ All secrets generated successfully"
    
    # Optionally save to files for docker-compose
    if [ "$1" = "--save-env" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        SECRETS_FILE="$SCRIPT_DIR/../../.env.secrets"
        ENV_FILE="$SCRIPT_DIR/../../.env"
        CONFIG_FILE="$SCRIPT_DIR/../../jstack.config"

        # Read DOMAIN and EMAIL from config if available
        if [ -f "$CONFIG_FILE" ]; then
            source "$CONFIG_FILE"
        fi

        # Save to both .env.secrets and .env (without auto-generated password)
        cat > "$SECRETS_FILE" << EOF
SUPABASE_JWT_SECRET=$JWT_SECRET
SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY
SUPABASE_PASSWORD=$SUPABASE_PASSWORD
EOF

        cat > "$ENV_FILE" << EOF
# Supabase Database Configuration
SUPABASE_JWT_SECRET=$JWT_SECRET
SUPABASE_ANON_KEY=$ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY
EMAIL=${EMAIL:-admin@example.com}
DOMAIN=${DOMAIN:-localhost}
SUPABASE_PASSWORD=$SUPABASE_PASSWORD

# AI Configuration (Required for Edge Functions)
# Edge functions use OpenRouter for AI processing (Gemini 2.5 Flash)
# Get your API key from: https://openrouter.ai/keys

OPENAI_BASE_URL=https://openrouter.ai/api/v1
#OPENAI_API_KEY=sk-or-v1-your-openrouter-key

# Alternative Options (uncomment one below if not using OpenRouter):

# Option 1: OpenAI API (Note: More expensive than OpenRouter)
#OPENAI_BASE_URL=https://api.openai.com/v1
#OPENAI_API_KEY=sk-your-openai-key

# Option 2: Anthropic Claude API (Direct)
#OPENAI_BASE_URL=https://api.anthropic.com/v1/
#OPENAI_API_KEY=sk-ant-your-anthropic-key

# Option 3: X.AI Grok
#OPENAI_BASE_URL=https://api.x.ai/v1
#OPENAI_API_KEY=xai-your-xai-key

# Option 4: Local LLM with OpenAI-compatible API (Ollama, LM Studio, etc)
#OPENAI_BASE_URL=http://host.docker.internal:11434/v1
#OPENAI_API_KEY=sk-no-key-required

# n8n Webhook Configuration
N8N_WEBHOOK_URL=https://n8n.${DOMAIN}
JARVIS_WEBHOOK_URL=your-webhook-goes-here
EOF
        log "✓ Secrets saved to $SECRETS_FILE and $ENV_FILE"
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