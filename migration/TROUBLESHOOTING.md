# Troubleshooting Guide

Common issues and their solutions for the Supabase migration tool.

## Setup Issues

### Node.js Not Found

**Error:** `node: command not found`

**Solution:**
```bash
# Check if Node.js is installed
which node

# Install Node.js if missing (Debian/Ubuntu)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### npm Install Fails

**Error:** `Cannot find module` or package errors

**Solution:**
```bash
# Clean npm cache
npm cache clean --force

# Remove node_modules and reinstall
rm -rf node_modules package-lock.json
npm install

# Or use the setup script
./setup.sh
```

### Module Type Error

**Error:** `SyntaxError: Cannot use import statement outside a module`

**Solution:**
```bash
# Ensure package.json has type set to module
npm pkg set type=module

# Or manually edit package.json
nano package.json
# Add: "type": "module"
```

## Connection Issues

### Cannot Connect to Source Database

**Error:** `Connection test failed` for source

**Solutions:**
```bash
# 1. Check credentials in .env
cat .env | grep SOURCE

# 2. Test connection directly
psql "$SOURCE_DATABASE_URL" -c "SELECT version();"

# 3. Verify password doesn't have special characters that need escaping
# URL encode special characters: @ = %40, # = %23, etc.

# 4. Check if IP is whitelisted in Supabase Cloud
# Go to: Supabase Dashboard → Settings → Database → Connection Pooling
# Add your IP address to allowed IPs
```

### Cannot Connect to Target Database

**Error:** `Connection test failed` for target

**Solutions:**
```bash
# 1. Check if PostgreSQL is running
docker-compose ps | grep postgres

# 2. Check credentials
cat /home/jarvis/jstack/.env.secrets | grep POSTGRES_PASSWORD

# 3. Test connection
psql "postgresql://postgres:YOUR_PASSWORD@localhost:5432/postgres" -c "SELECT version();"

# 4. Verify JStack is running
cd /home/jarvis/jstack
./jstack.sh status

# 5. Start JStack if needed
./jstack.sh up
```

### Connection Timeout

**Error:** `Connection timeout` or `ETIMEDOUT`

**Solutions:**
```bash
# 1. Check firewall rules
sudo ufw status

# 2. For Supabase Cloud, check database is not paused
# Dashboard → Settings → General → Pause project

# 3. Increase timeout in connection string
# Add: ?connect_timeout=30
TARGET_DATABASE_URL=postgresql://postgres:pass@localhost:5432/postgres?connect_timeout=30
```

## Migration Issues

### Tables Already Exist

**Error:** `relation "tablename" already exists`

**Solution:**
```bash
# Use --clean flag to drop existing tables first
node supabase-migration-script.js --clean --include-data

# WARNING: This deletes all data in target database!
```

### Missing Extensions

**Error:** `extension "vector" does not exist`

**Solution:**
```bash
# Connect to target database
psql "$TARGET_DATABASE_URL"

# Install missing extensions
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

# Exit
\q
```

### Foreign Key Constraint Violations

**Error:** `violates foreign key constraint`

**Solution:**
- This should be fixed in the latest version of the script
- If still occurring, try running with `--clean` flag
- The script now creates tables first, then adds foreign keys

### Sequence Does Not Exist

**Error:** `relation "tablename_id_seq" does not exist`

**Solution:**
- This is fixed in the latest version
- The script now creates sequences before tables
- Try running with `--clean` flag to start fresh

### Permission Denied

**Error:** `permission denied for schema public`

**Solutions:**
```bash
# 1. Use postgres superuser for target
TARGET_DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# 2. Grant permissions to user
psql "$TARGET_DATABASE_URL"
GRANT ALL ON SCHEMA public TO your_user;
GRANT ALL ON ALL TABLES IN SCHEMA public TO your_user;
\q
```

## Data Migration Issues

### Data Types Mismatch

**Error:** `column "columnname" is of type X but expression is of type Y`

**Solution:**
- The script handles most type conversions automatically
- For custom types, ensure they exist in target before migration
- Check migration report for type mismatches

### Large Data Sets Timeout

**Error:** Timeout during data migration

**Solutions:**
```bash
# 1. Increase batch size in script (if needed)
# 2. Migrate tables individually
# 3. Use --skip-schema if schema already migrated

# 4. Monitor progress
node supabase-migration-script.js --include-data 2>&1 | tee migration.log
```

### NULL Constraint Violations

**Error:** `null value in column "columnname" violates not-null constraint`

**Solutions:**
- Ensure source data integrity before migration
- Check if column has default value in source
- Use `--clean` flag to recreate schema properly

## Telegram ID Swap Issues

### IDs Not Being Replaced

**Problem:** Old telegram IDs still in target database

**Solutions:**
```bash
# 1. Verify environment variables are set
cat .env | grep TELEGRAM

# 2. Check script output for confirmation
# Should see: "🔄 Will swap Telegram IDs: OLD → NEW"

# 3. Verify --include-data flag is used
node supabase-migration-script.js --clean --include-data

# 4. Use command line argument instead
node supabase-migration-script.js --clean --include-data --swap-telegram-id=OLD:NEW
```

### Wrong Data Type for Telegram ID

**Problem:** ID swap not working for certain columns

**Solution:**
```bash
# The script handles both text and bigint columns
# Check column data types in source:
psql "$SOURCE_DATABASE_URL" -c "
  SELECT table_name, column_name, data_type
  FROM information_schema.columns
  WHERE column_name LIKE '%telegram%'
  ORDER BY table_name, column_name;
"
```

## Verification Issues

### Row Counts Don't Match

**Problem:** Different number of rows in source vs target

**Solutions:**
```bash
# 1. Check migration report
cat migration-report-*.json

# 2. Compare row counts manually
# Source:
psql "$SOURCE_DATABASE_URL" -c "SELECT COUNT(*) FROM tablename;"

# Target:
psql "$TARGET_DATABASE_URL" -c "SELECT COUNT(*) FROM tablename;"

# 3. Check for ON CONFLICT DO NOTHING in logs
# Duplicate keys may be skipped

# 4. Re-run with --clean flag
node supabase-migration-script.js --clean --include-data
```

### Functions Not Working

**Problem:** Database functions exist but don't execute properly

**Solutions:**
```bash
# 1. Check function definitions
psql "$TARGET_DATABASE_URL" -c "\df"

# 2. Verify dependencies (extensions, types)
psql "$TARGET_DATABASE_URL" -c "\dx"

# 3. Check for permission issues
psql "$TARGET_DATABASE_URL" -c "
  SELECT proname, proowner
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace;
"
```

## Environment File Issues

### .env Not Loading

**Problem:** Script doesn't see environment variables

**Solutions:**
```bash
# 1. Verify .env exists
ls -la .env

# 2. Check file format (no BOM, Unix line endings)
file .env

# 3. Verify dotenv is installed
npm list dotenv

# 4. Check script output
# Should see: "[dotenv@X.X.X] injecting env (N) from .env"

# 5. Manually source for testing
set -a
source .env
set +a
node supabase-migration-script.js
```

### Special Characters in Passwords

**Problem:** Connection fails with special characters in password

**Solution:**
```bash
# URL encode special characters in connection strings
# Common characters:
# @ = %40
# # = %23
# $ = %24
# & = %26
# : = %3A
# / = %2F

# Example:
# Password: my@pass#word
# Encoded: my%40pass%23word
SOURCE_DATABASE_URL=postgresql://postgres:my%40pass%23word@db.xxx.supabase.co:5432/postgres
```

## Performance Issues

### Migration Takes Too Long

**Solutions:**
```bash
# 1. Migrate schema first, then data separately
node supabase-migration-script.js  # Schema only
node supabase-migration-script.js --skip-schema --include-data  # Data only

# 2. Disable triggers during migration (already done by script)

# 3. Use faster disk I/O
# Check if target DB is on SSD

# 4. Increase PostgreSQL performance settings temporarily
# Edit postgresql.conf:
# shared_buffers = 256MB
# work_mem = 50MB
# maintenance_work_mem = 256MB
```

## Getting Help

If you're still stuck:

1. **Check the logs:** Look for specific error messages
2. **Review migration report:** Check `migration-report-*.json`
3. **Test connections:** Use `psql` to test database connections manually
4. **Verify setup:** Run `./setup.sh` again to ensure proper installation
5. **Check documentation:**
   - [README.md](./README.md) - Full documentation
   - [QUICKSTART.md](./QUICKSTART.md) - Quick start guide
   - [TELEGRAM_ID_SWAP.md](./TELEGRAM_ID_SWAP.md) - Telegram ID swap details

## Debug Mode

Run with additional logging:

```bash
# Enable PostgreSQL query logging
DEBUG=* node supabase-migration-script.js --include-data

# Save full output
node supabase-migration-script.js --include-data 2>&1 | tee migration-debug.log
```

## Still Need Help?

Create an issue with:
- Full error message
- Relevant .env configuration (redact passwords!)
- Migration report JSON
- Database versions (source and target)
- Command used
