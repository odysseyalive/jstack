#!/bin/bash
set -e

# Load configuration and secrets
CONFIG_FILE="$(dirname "$0")/../jstack.config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Load generated secrets
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Generate password if not set
if [ -z "$SUPABASE_PASSWORD" ]; then
    echo "SUPABASE_PASSWORD not found, generating new password..."
    SUPABASE_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
    export SUPABASE_PASSWORD
    echo "SUPABASE_PASSWORD=$SUPABASE_PASSWORD" >> "$ENV_FILE"
fi

echo "Fixing Supabase database user passwords..."

# Wait for database to be ready
until docker-compose exec supabase-db pg_isready -h localhost -U supabase_admin; do
  echo "Waiting for database to be ready..."
  sleep 2
done

echo "Database is ready. Updating user passwords..."

# Update passwords to match environment variables
docker-compose exec supabase-db psql -h localhost -U supabase_admin -d postgres -c "ALTER USER supabase_auth_admin WITH PASSWORD '$SUPABASE_PASSWORD';"
docker-compose exec supabase-db psql -h localhost -U supabase_admin -d postgres -c "ALTER USER authenticator WITH PASSWORD '$SUPABASE_PASSWORD';"
docker-compose exec supabase-db psql -h localhost -U supabase_admin -d postgres -c "ALTER USER postgres WITH PASSWORD '$SUPABASE_PASSWORD';"

echo "User passwords updated successfully."

# Restart services that depend on database authentication
echo "Restarting auth and rest services..."
docker-compose restart supabase-auth supabase-rest

echo "Supabase database password fix completed."