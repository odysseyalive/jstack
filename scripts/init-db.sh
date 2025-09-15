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
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
EOSQL

echo "Supabase database users created successfully."