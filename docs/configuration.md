# JStack Configuration Guide

This guide walks you through editing your `jstack.config` file step by step. The configuration file controls all the important settings for your JStack deployment.

## Getting Started

After copying `jstack.config.default` to `jstack.config`, you'll need to edit several key settings before running the installation.

```bash
cp jstack.config.default jstack.config
nano jstack.config
```

## Required Settings

### 1. Domain Configuration

**DOMAIN** - Your main domain name:
```bash
DOMAIN="example.com"
```
- Replace `example.com` with your actual domain
- Don't include `https://` or `www`
- Example: `mydomain.com` or `mycompany.org`

**EMAIL** - Your email for SSL certificates and admin contact:
```bash
EMAIL="admin@example.com"
```
- Use a real email address you control
- Let's Encrypt will send certificate expiration notices here
- Example: `yourname@yourdomain.com`

### 2. Service URLs

**N8N_URL** - Your n8n automation platform URL:
```bash
N8N_URL="n8n.example.com"
```
- Replace `example.com` with your domain
- This creates the full URL for accessing n8n

**SUPABASE_API_URL** - Your Supabase API URL:
```bash
SUPABASE_API_URL="api.example.com"
```
- Replace `example.com` with your domain
- This is where your Supabase API will be accessible

**SUPABASE_STUDIO_URL** - Your Supabase Studio URL:
```bash
SUPABASE_STUDIO_URL="studio.example.com"
```
- Replace `example.com` with your domain
- This is where you'll access the Supabase dashboard

**CHROME_URL** - Your Chrome/Puppeteer service URL:
```bash
CHROME_URL="chrome.example.com"
```
- Replace `example.com` with your domain
- This is for browser automation tasks

### 3. SSL Configuration

**SSL_ENABLED** - Enable SSL certificates:
```bash
SSL_ENABLED=true
```
- Set to `true` for production (recommended)
- Set to `false` only for testing/development

**SSL Certificate Details:**
```bash
SSL_COUNTRY="US"
SSL_STATE="Oregon"
SSL_CITY="Portland" 
SSL_ORGANIZATION="Organization"
SSL_ORG_UNIT="Development"
```
- Update these with your actual location and organization details
- Used for SSL certificate generation

### 4. Supabase Database Configuration

**SUPABASE_DB** - Database name:
```bash
SUPABASE_DB="postgres"
```
- Usually leave as "postgres" (default)

> **Note**: Supabase security keys (JWT secret, ANON key, SERVICE_ROLE key) and database password are automatically generated during installation for better security.

## Automated Security Features

JStack automatically generates secure secrets during installation:

- **JWT Secret**: A 64-character cryptographically secure secret for JWT token signing
- **Database Password**: Set interactively during installation with secure prompting
- **API Keys**: Supabase ANON and SERVICE_ROLE keys generated with proper JWT claims
- **Environment Variables**: All secrets are injected into containers without storing in config files

This approach ensures:
- No hardcoded secrets in configuration files
- Unique secrets for each installation
- Proper cryptographic strength for all generated keys

## Optional Settings

### Backup Configuration

**BACKUP_ENABLED** - Enable automatic backups:
```bash
BACKUP_ENABLED=true
```
- Set to `true` to enable automated backups (recommended)
- Set to `false` to disable backups

### Service Ports (Advanced)

These are pre-configured and usually don't need changes:
```bash
NGINX_PORT=443
SUPABASE_DB_PORT=5432
SUPABASE_API_PORT=8000
SUPABASE_STUDIO_PORT=3001
N8N_PORT=5678
CHROME_PORT=3000
```

### Environment Settings

**N8N_ENV** - n8n environment:
```bash
N8N_ENV="production"
```
- Use "production" for live deployments
- Use "development" for testing

**DRY_RUN** - Enable dry-run mode:
```bash
DRY_RUN=false
```
- Set to `true` to preview actions without executing them
- Set to `false` for normal operation

**DEBUG** - Enable debug logging:
```bash
DEBUG=false
```
- Set to `true` for verbose logging (helpful for troubleshooting)
- Set to `false` for normal operation

## Example Complete Configuration

Here's what a typical `jstack.config` file looks like:

```bash
# Domain and SSL
DOMAIN="mycompany.com"
EMAIL="admin@mycompany.com"
SSL_ENABLED=true

# SSL Certificate Details
SSL_COUNTRY="US"
SSL_STATE="California"
SSL_CITY="San Francisco"
SSL_ORGANIZATION="My Company Inc"
SSL_ORG_UNIT="IT Department"

# Service Subdomains
N8N_URL="n8n.mycompany.com"
SUPABASE_API_URL="api.mycompany.com"
SUPABASE_STUDIO_URL="studio.mycompany.com"
CHROME_URL="chrome.mycompany.com"

# Ports (usually no changes needed)
NGINX_PORT=443
SUPABASE_DB_PORT=5432
SUPABASE_API_PORT=8000
SUPABASE_STUDIO_PORT=3001
N8N_PORT=5678
CHROME_PORT=3000

# Supabase Configuration
SUPABASE_DB="postgres"

# n8n
N8N_ENV="production"

# Dry-run and backup
DRY_RUN=false
BACKUP_ENABLED=true

# Debug
DEBUG=false
```

## DNS Requirements

Before running the installation, make sure your DNS is configured:

1. **A Record**: Point your main domain to your server's IP
   - `mycompany.com` → `192.168.1.100`

2. **CNAME Records**: Point subdomains to your main domain
   - `api.mycompany.com` → `mycompany.com`
   - `n8n.mycompany.com` → `mycompany.com`
   - `studio.mycompany.com` → `mycompany.com`
   - `chrome.mycompany.com` → `mycompany.com`

## Validation

After editing your config, validate it before installation:

```bash
./jstack.sh validate
```

This will check for common configuration errors and DNS issues.

## Common Mistakes

1. **Including protocol in domain**: Use `example.com`, not `https://example.com`
2. **Wrong email format**: Use a real email address for SSL certificates
3. **Missing DNS records**: All subdomains must resolve to your server
4. **Special characters**: Avoid spaces and special characters in domain names

## Getting Help

If you're stuck on configuration:
- Check [docs/troubleshooting.md](troubleshooting.md) for common issues
- Run `./jstack.sh --dry-run` to preview what will happen
- Open a [GitHub Issue](https://github.com/odysseyalive/jstack/issues) for help