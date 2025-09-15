#!/bin/bash
set -e

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