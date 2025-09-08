# 🛠️ CLI Reference - jstack.sh Commands

> Complete command-line reference for JarvisJR Stack management

## Overview

The `jstack.sh` script is the main orchestrator for all JarvisJR Stack operations. It follows a modular architecture where all business logic is handled by specialized scripts, while the main CLI provides clean command routing.

---

## Core Commands

### Installation and Setup

```bash
# Deploy complete JarvisJR Stack infrastructure
./jstack.sh

# Validate configuration before deployment
./jstack.sh --validate

# Dry run deployment (validation only, no changes)
./jstack.sh --dry-run
```

### System Management

```bash
# Check status of all services
./jstack.sh --status

# Restart all services
./jstack.sh --restart

# Stop all services
./jstack.sh --stop

# Start all services
./jstack.sh --start

# Complete system uninstall
./jstack.sh --uninstall

# Update JarvisJR Stack from repository
./jstack.sh --sync
```

### Service-Specific Operations

```bash
# Restart individual services
./jstack.sh --restart-n8n
./jstack.sh --restart-db
./jstack.sh --restart-nginx

# View service logs
./jstack.sh --logs
./jstack.sh --logs --service n8n
./jstack.sh --logs --service supabase
```

---

## Site Template Commands

### Site Deployment

```bash
# Deploy site with template (basic)
./jstack.sh --add-site DOMAIN --template TEMPLATE_NAME

# Deploy site with custom template directory
./jstack.sh --add-site DOMAIN --template /path/to/template/

# Deploy with verbose output
./jstack.sh --add-site DOMAIN --template TEMPLATE_NAME --verbose

# Dry run site deployment (validation only)
./jstack.sh --add-site DOMAIN --template TEMPLATE_NAME --dry-run
```

**Examples:**
```bash
# Deploy Next.js business site
./jstack.sh --add-site mybusiness.com --template nextjs-business

# Deploy Hugo portfolio
./jstack.sh --add-site myportfolio.com --template hugo-portfolio  

# Deploy LAMP web application
./jstack.sh --add-site myapp.com --template lamp-webapp

# Deploy custom template
./jstack.sh --add-site mysite.com --template ~/my-custom-site/
```

### Site Management

```bash
# List all deployed sites
./jstack.sh --list-sites

# Remove a site completely
./jstack.sh --remove-site DOMAIN

# Show site information
./jstack.sh --site-info DOMAIN

# Update site configuration
./jstack.sh --update-site DOMAIN
```

**Examples:**
```bash
# List all sites
./jstack.sh --list-sites

# Remove a site
./jstack.sh --remove-site old-site.com
```

### Template Validation

```bash
# Validate template structure and configuration
./jstack.sh --validate-template TEMPLATE_PATH

# List available built-in templates
./jstack.sh --list-templates

# Show template information
./jstack.sh --template-info TEMPLATE_NAME
```

**Examples:**
```bash
# Validate built-in template
./jstack.sh --validate-template templates/nextjs-business/

# Validate custom template
./jstack.sh --validate-template ~/my-custom-template/

# List available templates
./jstack.sh --list-templates
```

---

## SSL and Domain Management

### SSL Certificates

```bash
# Configure SSL for domain (automatic with --add-site)
./jstack.sh --configure-ssl DOMAIN

# Renew SSL certificate
./jstack.sh --renew-ssl DOMAIN

# Check SSL certificate status
./jstack.sh --ssl-status DOMAIN

# Force SSL certificate regeneration
./jstack.sh --force-ssl DOMAIN
```

### NGINX Configuration

```bash
# Test NGINX configuration
./jstack.sh --test-nginx

# Test NGINX configuration for specific domain  
./jstack.sh --test-nginx DOMAIN

# Reload NGINX configuration
./jstack.sh --reload-nginx

# Generate NGINX configuration for domain
./jstack.sh --generate-nginx-config DOMAIN
```

---

## Backup and Recovery

### Backup Operations

```bash
# Create timestamped backup
./jstack.sh --backup

# Create named backup
./jstack.sh --backup BACKUP_NAME

# List available backups
./jstack.sh --list-backups

# Show backup information
./jstack.sh --backup-info BACKUP_FILE
```

### Restore Operations

```bash
# Interactive restore (select from list)
./jstack.sh --restore

# Restore specific backup
./jstack.sh --restore BACKUP_FILE

# Restore with verification
./jstack.sh --restore BACKUP_FILE --verify
```

### Site-Specific Backups

```bash
# Backup specific site
./jstack.sh --backup-site DOMAIN

# Restore specific site
./jstack.sh --restore-site DOMAIN BACKUP_FILE

# List site backups
./jstack.sh --list-site-backups DOMAIN
```

---

## Security and Compliance

### Security Operations

```bash
# Run security scan
./jstack.sh --security-scan

# Check security status
./jstack.sh --security-status

# View security logs
./jstack.sh --security-logs

# Update security rules
./jstack.sh --update-security

# Enable/disable security features
./jstack.sh --enable-security FEATURE
./jstack.sh --disable-security FEATURE
```

### Compliance Monitoring

```bash
# Run compliance check
./jstack.sh --compliance-check

# Generate compliance report
./jstack.sh --compliance-report

# Update compliance documentation
./jstack.sh --update-compliance-docs

# Check compliance status for site
./jstack.sh --compliance-status DOMAIN
```

---

## Monitoring and Health

### Health Checks

```bash
# Complete system health check
./jstack.sh --health-check

# Check specific service health
./jstack.sh --health-check --service SERVICE_NAME

# Run diagnostics
./jstack.sh --diagnostics

# System metrics
./jstack.sh --metrics
```

### Monitoring

```bash
# Enable monitoring dashboard
./jstack.sh --enable-monitoring

# Disable monitoring dashboard
./jstack.sh --disable-monitoring

# View monitoring status
./jstack.sh --monitoring-status
```

---

## Configuration Management

### Configuration Operations

```bash
# Validate current configuration
./jstack.sh --validate-config

# Test DNS configuration
./jstack.sh --test-dns

# Show current configuration
./jstack.sh --show-config

# Update configuration from file
./jstack.sh --update-config

# Reset configuration to defaults
./jstack.sh --reset-config
```

### Credentials Management

```bash
# Show generated credentials
./jstack.sh --show-credentials

# Regenerate credentials
./jstack.sh --regenerate-credentials

# Rotate credentials
./jstack.sh --rotate-credentials SERVICE_NAME
```

---

## Debug and Development

### Debug Operations

```bash
# Enable debug mode
./jstack.sh --enable-debug

# Disable debug mode  
./jstack.sh --disable-debug

# View debug logs
./jstack.sh --debug-logs

# Run in verbose mode
./jstack.sh COMMAND --verbose
```

### Development Tools

```bash
# Pre-deployment checks
./jstack.sh --pre-check

# Test all connections
./jstack.sh --test-connections

# Validate system requirements
./jstack.sh --validate-requirements

# Show system information
./jstack.sh --system-info
```

---

## Built-in Templates

### Available Templates

| Template Name | Description | Tech Stack | Use Case |
|---------------|-------------|------------|----------|
| `nextjs-business` | Next.js business website | Next.js 14, React, Node.js 22 | Business sites, web apps |
| `hugo-portfolio` | Hugo static site | Hugo, Tailwind CSS | Portfolios, blogs, docs |
| `lamp-webapp` | LAMP stack application | PHP 8.2, Apache, MariaDB | PHP apps, CMSs, WordPress |

### Template Structure

Each template includes:
- `site.json` - Site configuration
- `docker-compose.yml` - Container orchestration  
- `docs/` - Template documentation
- Source code and configuration files
- Deployment and build scripts

---

## Global Options

### Common Flags

```bash
--dry-run          # Validate only, make no changes
--verbose          # Enable verbose output
--debug           # Enable debug mode
--quiet           # Suppress non-essential output
--force           # Force operation without confirmation
--yes             # Answer yes to all prompts
```

### Environment Variables

```bash
# Override configuration file location
JSTACK_CONFIG=/path/to/config

# Enable debug mode
DEBUG=true

# Set dry run mode
DRY_RUN=true

# Custom base directory
BASE_DIR=/custom/path
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Network/DNS error |
| 4 | SSL certificate error |
| 5 | Docker/container error |
| 6 | Permission error |
| 10 | Validation failed |
| 11 | Template error |
| 20 | Backup/restore error |

---

## Usage Examples

### Complete Deployment Workflow

```bash
# 1. Configure
cp jstack.config.default jstack.config
nano jstack.config  # Edit DOMAIN and EMAIL

# 2. Validate
./jstack.sh --validate

# 3. Deploy infrastructure
./jstack.sh

# 4. Deploy websites
./jstack.sh --add-site mybusiness.com --template nextjs-business
./jstack.sh --add-site blog.mybusiness.com --template hugo-portfolio

# 5. Create backup
./jstack.sh --backup initial-deployment

# 6. Check status
./jstack.sh --status
./jstack.sh --list-sites
```

### Site Management Workflow

```bash
# Copy and customize template
cp -r templates/nextjs-business/ ~/my-site/
cd ~/my-site/
nano site.json  # Edit configuration
nano src/app/page.tsx  # Customize code

# Validate template
./jstack.sh --validate-template ~/my-site/

# Test deployment
./jstack.sh --add-site mysite.com --template ~/my-site/ --dry-run

# Deploy
./jstack.sh --add-site mysite.com --template ~/my-site/

# Verify
curl -I https://mysite.com
./jstack.sh --site-info mysite.com
```

### Maintenance Workflow

```bash
# Daily maintenance
./jstack.sh --health-check
./jstack.sh --security-status
./jstack.sh --backup daily-$(date +%Y%m%d)

# Weekly maintenance  
./jstack.sh --update
./jstack.sh --security-scan
./jstack.sh --compliance-check

# Monthly maintenance
./jstack.sh --rotate-credentials
./jstack.sh --cleanup-logs
./jstack.sh --update-security
```

---

## Getting Help

```bash
# Show help information
./jstack.sh --help
./jstack.sh -h

# Show version information
./jstack.sh --version
./jstack.sh -v

# Show command-specific help
./jstack.sh COMMAND --help
```

For more detailed documentation:
- **📚 [Installation Guide](../guides/installation.md)** - Complete setup instructions
- **🌐 [Site Templates Guide](../guides/site-templates.md)** - Template deployment guide
- **⚙️ [Configuration Guide](../guides/configuration.md)** - Configuration options
- **🔒 [Security Guide](security.md)** - Security features and compliance
- **🏗️ [Architecture Guide](architecture.md)** - System architecture details