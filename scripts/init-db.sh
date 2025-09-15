#!/bin/bash
set -e

echo "Creating Supabase database users..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER supabase_auth_admin WITH PASSWORD '$SUPABASE_PASSWORD';
    CREATE USER authenticator WITH PASSWORD '$SUPABASE_PASSWORD';
    CREATE USER postgres WITH SUPERUSER PASSWORD '$SUPABASE_PASSWORD';
    CREATE ROLE anon NOLOGIN NOINHERIT;
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    
    -- Create required schemas
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS storage;
    CREATE SCHEMA IF NOT EXISTS realtime;
    CREATE SCHEMA IF NOT EXISTS _realtime;
    CREATE SCHEMA IF NOT EXISTS graphql_public;
    
    -- Grant schema permissions
    GRANT ALL PRIVILEGES ON SCHEMA public TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON SCHEMA auth TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON SCHEMA storage TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO supabase_auth_admin;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;
    
    GRANT ALL PRIVILEGES ON SCHEMA public TO authenticator;
    GRANT ALL PRIVILEGES ON SCHEMA auth TO authenticator;
    GRANT ALL PRIVILEGES ON SCHEMA storage TO authenticator;
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO authenticator;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO authenticator;
    ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO authenticator;
    
    -- Grant roles to authenticator
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
EOSQL

echo "Supabase database users created successfully."