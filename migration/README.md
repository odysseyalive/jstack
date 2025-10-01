# Supabase Cloud to Self-Hosted Migration

Complete guide for migrating your Supabase Cloud database to a self-hosted Supabase instance.

---

## Quick Start - 5 Minutes to Migration

### Step 1: Run Setup (30 seconds)

```bash
cd /home/jarvis/jstack/migration
./setup.sh
```

This installs all dependencies and creates your `.env` file.

### Step 2: Configure Credentials (2 minutes)

Edit the `.env` file:

```bash
nano .env
```

Get your credentials from Supabase Cloud dashboard:

**Get SOURCE_SUPABASE_URL and SOURCE_SUPABASE_ANON_KEY:**
1. Go to https://app.supabase.com
2. Select your project
3. Click **Settings** → **API**
4. Copy **Project URL** → paste as `SOURCE_SUPABASE_URL`
5. Copy **anon public** key → paste as `SOURCE_SUPABASE_ANON_KEY`

**Get SOURCE_DATABASE_URL:**
1. In same Supabase project
2. Click **Settings** → **Database**
3. Scroll to **Connection string**
4. Click **URI** tab
5. Copy the connection string
6. Replace `[YOUR-PASSWORD]` with your actual database password
7. Paste as `SOURCE_DATABASE_URL`

**Get TARGET_DATABASE_URL (Self-hosted):**
```bash
# View your self-hosted password
cat /home/jarvis/jstack/.env.secrets | grep POSTGRES_PASSWORD

# Use this format:
# TARGET_DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@localhost:5432/postgres
```

**Optional: Set Telegram ID Swap:**
```env
OLD_TELEGRAM_ID=123456789
NEW_TELEGRAM_ID=987654321
```

Save and exit (Ctrl+X, Y, Enter).

### Step 3: Run Migration (2 minutes)

**Test First (Schema Only):**
```bash
node supabase-migration-script.js
```

**Full Migration (Clean + Data):**
```bash
node supabase-migration-script.js --clean --include-data
```

**With Telegram ID Swap:**
```bash
# Already configured in .env, just run:
node supabase-migration-script.js --clean --include-data
```

### Step 4: Verify Migration

```bash
# Connect to your self-hosted database
psql "postgresql://postgres:YOUR_PASSWORD@localhost:5432/postgres"

# Check tables
\dt

# Check row counts
SELECT 'contacts' as table_name, COUNT(*) FROM contacts
UNION ALL
SELECT 'messages', COUNT(*) FROM messages
UNION ALL
SELECT 'notes', COUNT(*) FROM notes;

# Exit
\q
```

---

## Detailed Documentation

### Prerequisites

- Node.js installed
- Access to your Supabase Cloud project
- Self-hosted Supabase instance running (via JStack)
- PostgreSQL connection string for both source and target

### Installation

**Option A: Automated Setup (Recommended)**

```bash
cd /home/jarvis/jstack/migration
./setup.sh
```

This will automatically:
- Initialize npm project with `"type": "module"`
- Install all required packages
- Create `.env` file from template
- Show you next steps

**Option B: Manual Setup**

```bash
cd /home/jarvis/jstack/migration

# Initialize npm if package.json doesn't exist
npm init -y

# Set module type
npm pkg set type=module

# Install required packages
npm install @supabase/supabase-js pg dotenv node-fetch
```

**Required packages:**
- `@supabase/supabase-js` - Supabase client library
- `pg` - PostgreSQL client for Node.js
- `dotenv` - Load environment variables from .env file
- `node-fetch` - Fetch API for Node.js

### Configuration

Create a `.env` file from the example template:

```bash
# Copy the example file
cp .env.example .env

# Edit with your credentials
nano .env
```

**Example .env file:**
```env
# Source (Supabase Cloud)
SOURCE_SUPABASE_URL=https://xxxxx.supabase.co
SOURCE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SOURCE_DATABASE_URL=postgresql://postgres:password@db.xxxxx.supabase.co:5432/postgres

# Target (Self-hosted)
TARGET_DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# Optional: Telegram ID Swap
OLD_TELEGRAM_ID=123456789
NEW_TELEGRAM_ID=987654321
```

**Where to find credentials:**

**Supabase Cloud:**
1. Go to https://app.supabase.com
2. Select your project
3. **For URL and Keys:** Settings → API
   - Copy "Project URL" → `SOURCE_SUPABASE_URL`
   - Copy "anon public" key → `SOURCE_SUPABASE_ANON_KEY`
4. **For Database URL:** Settings → Database → Connection string
   - Select "URI" tab
   - Copy the connection string → `SOURCE_DATABASE_URL`
   - Replace `[YOUR-PASSWORD]` with your actual database password

**Self-hosted (JStack):**
1. `TARGET_DATABASE_URL` uses the format: `postgresql://postgres:[PASSWORD]@[HOST]:[PORT]/postgres`
2. Default for local JStack: `postgresql://postgres:your-password@localhost:5432/postgres`
3. Find your password in `/home/jarvis/jstack/.env.secrets` under `POSTGRES_PASSWORD`

---

## Telegram ID Swap Feature

The migration script supports swapping Telegram IDs during data migration. This is useful when migrating data to a new bot or different Telegram account.

### How It Works

The script automatically detects and replaces telegram IDs in **any column** that contains "telegram_id" or "telegram_username" in its name.

**Column types supported:**
- Text/varchar columns: `user_telegram_id`, `chat_telegram_id`, `telegram_username`
- Bigint columns: `telegram_id`

**How it works:**
- For **text columns**: String comparison and replacement
- For **bigint columns**: Numeric comparison and replacement (supports large integers)
- Null values are preserved
- Non-matching values are preserved

### Tables Affected

Based on your schema, these tables will have their telegram IDs updated:
- `contacts` - user_telegram_id, telegram_username, telegram_id
- `images` - user_telegram_id, chat_telegram_id
- `messages` - user_telegram_id, chat_telegram_id
- `notes` - user_telegram_id
- `scheduled_tasks` - user_telegram_id

### Usage Methods

**Method 1: Environment Variables (Recommended)**

Add to your `.env` file:
```env
OLD_TELEGRAM_ID=123456789
NEW_TELEGRAM_ID=987654321
```

Then run:
```bash
node supabase-migration-script.js --clean --include-data
```

**Method 2: Command Line Argument**

```bash
node supabase-migration-script.js --clean --include-data --swap-telegram-id=123456789:987654321
```

### Verify Swap is Active

The script will show this when it starts if telegram ID swap is configured:
```
🔄 Telegram ID mapping configured: 123456789 → 987654321
```

During data migration:
```
🔄 Will swap Telegram IDs: 123456789 → 987654321
```

---

## Migration Options

| Option | Description |
|--------|-------------|
| `--include-data` | Migrate table data (default: schema only) |
| `--include-auth` | Export auth users to JSON (passwords cannot be migrated) |
| `--skip-schema` | Skip schema migration (only migrate data/functions) |
| `--clean` | Drop all existing tables before migration (WARNING: destructive) |
| `--swap-telegram-id=OLD:NEW` | Replace telegram IDs during migration |
| `--help` | Show help message |

## What Gets Migrated

✅ **Automatically Migrated:**
- Database schemas (public schema)
- Tables with all columns and data types
- Primary keys and unique constraints
- Foreign key constraints
- Indexes (including GIN, BTREE, etc.)
- Custom PostgreSQL types (enums, etc.)
- Database functions (SQL/PLPGSQL)
- Triggers
- Row Level Security (RLS) policies
- Views
- Sequences
- Table data (with `--include-data`)

⚠️ **Needs Manual Setup:**
- Auth users (exported to `auth-users-export.json`, passwords cannot be migrated)
- Storage buckets (configuration saved to `storage-buckets-config.json`)
- Edge Functions (copied to `migrated-edge-functions/` with deploy instructions)
- Storage files (must be manually copied)

❌ **Not Migrated:**
- Supabase Cloud-specific features
- Realtime subscriptions configuration
- API rate limits and quotas

## Common Issues

### Connection Issues

**Error: "Connection test failed"**
```bash
# Test source connection
psql "$SOURCE_DATABASE_URL" -c "SELECT version();"

# Test target connection
psql "$TARGET_DATABASE_URL" -c "SELECT version();"
```

**Check credentials:**
- Verify `.env` file has correct values
- Ensure passwords don't have unescaped special characters
- Confirm JStack is running: `cd /home/jarvis/jstack && ./jstack.sh status`

### Migration Issues

**Error: "relation already exists"**
- Use the `--clean` flag to drop existing tables first
- Warning: This deletes all data in target database

**Error: "permission denied"**
- Make sure your PostgreSQL user has sufficient privileges
- For self-hosted, use the `postgres` superuser

**Error: "extension does not exist"**
```bash
# Connect to target database and install extensions
psql "$TARGET_DATABASE_URL"
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";
\q
```

### Data Issues

**Tables exist but have no data:**
- Check that you used `--include-data` flag
- Verify foreign key dependencies (script now handles this automatically)

**Telegram IDs not swapping:**
- Verify `OLD_TELEGRAM_ID` and `NEW_TELEGRAM_ID` are set in `.env`
- Check script output for "🔄 Telegram ID mapping configured" message
- Ensure `--include-data` flag is used (swap only happens during data migration)

## Troubleshooting

For comprehensive troubleshooting, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

Quick fixes:
- **Connection timeout:** Check firewall, verify database isn't paused
- **Slow migration:** Tables migrate in dependency order, be patient
- **Missing data:** Ensure `--include-data` flag is used
- **Wrong telegram IDs:** Re-run with correct `OLD_TELEGRAM_ID` and `NEW_TELEGRAM_ID`

## Migration Checklist

- [ ] Backup your source database
- [ ] Set up `.env` file with correct credentials
- [ ] Test connection with schema-only migration
- [ ] Review migration report
- [ ] Run full migration with `--clean --include-data`
- [ ] Verify table structure in target database
- [ ] Verify data integrity (row counts, sample data)
- [ ] Verify telegram IDs were swapped (if using that feature)
- [ ] Update application connection strings
- [ ] Test application functionality
- [ ] Set up backups for self-hosted instance

## File Structure

```
migration/
├── .env                              # Your credentials (DO NOT COMMIT)
├── .env.example                      # Example configuration template
├── .gitignore                        # Protects sensitive files
├── setup.sh                          # Automated setup script
├── supabase-migration-script.js      # Main migration script
├── package.json                      # Dependencies
├── README.md                         # This file
├── TROUBLESHOOTING.md               # Comprehensive troubleshooting guide
├── migration-report-*.json          # Generated after migration
├── auth-users-export.json           # Exported auth users (if using --include-auth)
├── storage-buckets-config.json      # Storage bucket configuration
└── migrated-edge-functions/         # Copied edge functions (if any)
```

## Security Notes

⚠️ **Important:**
- Never commit `.env` file to version control
- Keep database passwords secure
- Auth user passwords cannot be migrated (security feature)
- Users will need to reset passwords after migration
- Review RLS policies after migration

## Advanced Usage

### Migrate Schema First, Then Data

```bash
# Step 1: Migrate schema only
node supabase-migration-script.js --clean

# Step 2: Verify schema looks correct
psql "$TARGET_DATABASE_URL" -c "\dt"

# Step 3: Migrate data
node supabase-migration-script.js --skip-schema --include-data
```

### Debug Mode

Run with full output logging:

```bash
# Save full output to file
node supabase-migration-script.js --clean --include-data 2>&1 | tee migration-debug.log
```

## Support

For issues with:
- **Migration script:** Check logs in console output and migration report
- **JStack setup:** Refer to `/home/jarvis/jstack/CLAUDE.md`
- **Supabase:** https://supabase.com/docs

## Additional Resources

- [Troubleshooting Guide](./TROUBLESHOOTING.md) - Comprehensive troubleshooting
- [Supabase Self-Hosting Guide](https://supabase.com/docs/guides/self-hosting)
- [JStack Documentation](../CLAUDE.md)

---

That's it! Your data should now be migrated to your self-hosted Supabase instance. 🎉
