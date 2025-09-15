#!/bin/bash
set -e

echo "Creating Supabase database users..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create users
    CREATE USER supabase_auth_admin WITH PASSWORD '$SUPABASE_PASSWORD';
    CREATE USER authenticator WITH PASSWORD '$SUPABASE_PASSWORD';
    CREATE USER postgres WITH SUPERUSER PASSWORD '$SUPABASE_PASSWORD';
    
    -- Create basic roles
    CREATE ROLE anon NOLOGIN NOINHERIT;
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    
    -- Create basic schemas
    CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
    CREATE SCHEMA IF NOT EXISTS storage;
    CREATE SCHEMA IF NOT EXISTS realtime;
    CREATE SCHEMA IF NOT EXISTS _realtime;
    CREATE SCHEMA IF NOT EXISTS graphql_public;
    
    -- Grant broad permissions
    GRANT ALL ON SCHEMA public TO supabase_auth_admin, authenticator;
    GRANT ALL ON SCHEMA auth TO supabase_auth_admin, authenticator;
    GRANT ALL ON SCHEMA storage TO supabase_auth_admin, authenticator;
    GRANT ALL ON ALL TABLES IN SCHEMA public TO supabase_auth_admin, authenticator;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO supabase_auth_admin, authenticator;
    
    -- Set default privileges
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO supabase_auth_admin, authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin, authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO supabase_auth_admin, authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin, authenticator;
    
    -- Grant roles to authenticator
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
EOSQL

echo "Supabase database users created successfully."