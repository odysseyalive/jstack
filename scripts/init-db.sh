#!/bin/bash
set -e

# Database initialization script for Supabase
# Creates required users and databases

echo "Creating Supabase database users..."

# Create supabase_auth_admin user
psql -v ON_ERROR_STOP=1 --username supabase_admin --dbname postgres <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_auth_admin') THEN
            CREATE USER supabase_auth_admin WITH PASSWORD '${SUPABASE_PASSWORD}';
        END IF;
    END
    \$\$;
    
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticator') THEN
            CREATE USER authenticator WITH PASSWORD '${SUPABASE_PASSWORD}';
        END IF;
    END
    \$\$;
    
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'postgres') THEN
            CREATE USER postgres WITH SUPERUSER PASSWORD '${SUPABASE_PASSWORD}';
        END IF;
    END
    \$\$;
    
    -- Grant necessary permissions
    GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON DATABASE postgres TO authenticator;
    
    -- Create roles for Supabase
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'anon') THEN
            CREATE ROLE anon NOLOGIN NOINHERIT;
        END IF;
    END
    \$\$;
    
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
            CREATE ROLE authenticated NOLOGIN NOINHERIT;
        END IF;
    END
    \$\$;
    
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'service_role') THEN
            CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
        END IF;
    END
    \$\$;
    
    -- Grant permissions to authenticator
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
EOSQL

echo "Supabase database users created successfully."