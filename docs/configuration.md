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

**DOMAIN_BASE** - Your main domain name:
```bash
DOMAIN_BASE="example.com"
```
- Replace `example.com` with your actual domain
- Don't include `https://` or `www`
- Example: `mydomain.com` or `mycompany.org`

**SUBDOMAIN_API** - API subdomain:
```bash
SUBDOMAIN_API="api"
```
- This creates `api.yourdomain.com`
- Leave as "api" unless you have a specific preference

**SUBDOMAIN_N8N** - n8n automation subdomain:
```bash
SUBDOMAIN_N8N="n8n"
```
- This creates `n8n.yourdomain.com`
- Leave as "n8n" unless you have a specific preference

**SUBDOMAIN_STUDIO** - Supabase Studio subdomain:
```bash
SUBDOMAIN_STUDIO="studio"
```
- This creates `studio.yourdomain.com`
- Leave as "studio" unless you have a specific preference

**SUBDOMAIN_CHROME** - Chrome/Puppeteer subdomain:
```bash
SUBDOMAIN_CHROME="chrome"
```
- This creates `chrome.yourdomain.com`
- Leave as "chrome" unless you have a specific preference

### 2. SSL Certificate Email

**SSL_EMAIL** - Your email for Let's Encrypt certificates:
```bash
SSL_EMAIL="admin@example.com"
```
- Use a real email address you control
- Let's Encrypt will send certificate expiration notices here
- Example: `yourname@yourdomain.com`

### 3. Environment Settings

**ENVIRONMENT** - Deployment environment:
```bash
ENVIRONMENT="production"
```
- Use "production" for live deployments
- Use "development" for testing setups

## Optional Settings

### Backup Configuration

**BACKUP_RETENTION_DAYS** - How long to keep backups:
```bash
BACKUP_RETENTION_DAYS=30
```
- Default is 30 days
- Adjust based on your storage needs

### Service Ports (Advanced)

These are pre-configured and usually don't need changes:
```bash
SUPABASE_DB_PORT=5432
N8N_PORT=5678
CHROME_PORT=9222
```

## Example Complete Configuration

Here's what a typical `jstack.config` file looks like:

```bash
# Domain Configuration
DOMAIN_BASE="mycompany.com"
SUBDOMAIN_API="api"
SUBDOMAIN_N8N="n8n"
SUBDOMAIN_STUDIO="studio"
SUBDOMAIN_CHROME="chrome"

# SSL Configuration
SSL_EMAIL="admin@mycompany.com"

# Environment
ENVIRONMENT="production"

# Backup Settings
BACKUP_RETENTION_DAYS=30

# Service Ports (usually no changes needed)
SUPABASE_DB_PORT=5432
N8N_PORT=5678
CHROME_PORT=9222
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