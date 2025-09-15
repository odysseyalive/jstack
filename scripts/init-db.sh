#!/bin/bash
set -e

# Database initialization script for Supabase
# Creates required users and databases

echo "Creating Supabase database users..."

# Create supabase_auth_admin user
psql -v ON_ERROR_STOP=1 --username supabase_admin --dbname postgres <<-EOSQL
    CREATE USER IF NOT EXISTS supabase_auth_admin WITH PASSWORD '${SUPABASE_PASSWORD}';
    CREATE USER IF NOT EXISTS authenticator WITH PASSWORD '${SUPABASE_PASSWORD}';
    CREATE USER IF NOT EXISTS postgres WITH SUPERUSER PASSWORD '${SUPABASE_PASSWORD}';
    
    -- Grant necessary permissions
    GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON DATABASE postgres TO authenticator;
    
    -- Create roles for Supabase
    CREATE ROLE IF NOT EXISTS anon NOLOGIN NOINHERIT;
    CREATE ROLE IF NOT EXISTS authenticated NOLOGIN NOINHERIT;
    CREATE ROLE IF NOT EXISTS service_role NOLOGIN NOINHERIT BYPASSRLS;
    
    -- Grant permissions to authenticator
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
EOSQL

echo "Supabase database users created successfully."