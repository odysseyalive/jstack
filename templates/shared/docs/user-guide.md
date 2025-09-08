# COMPASS Stack Site Templates User Guide

This guide explains how to use the COMPASS Stack template system to quickly deploy websites and web applications.

## Table of Contents

1. [Overview](#overview)
2. [Available Templates](#available-templates)
3. [Quick Start](#quick-start)
4. [Template Deployment](#template-deployment)
5. [Customization](#customization)
6. [Management](#management)
7. [Troubleshooting](#troubleshooting)

## Overview

The COMPASS Stack template system provides pre-configured, production-ready website templates that can be deployed instantly with proper security, SSL certificates, and monitoring.

### Key Features

- **One-command deployment**: Deploy complete websites with a single command
- **Automatic SSL**: Let's Encrypt SSL certificates configured automatically
- **Security hardened**: All templates follow security best practices
- **Production ready**: Optimized Docker configurations for production
- **Compliance monitoring**: Integrated with COMPASS Stack compliance system
- **Backup support**: Automatic backup and restore capabilities

### Prerequisites

Before using templates, ensure you have:

- COMPASS Stack installed and configured
- Domain pointing to your server
- Email configured in `jstack.config` for SSL certificates
- Docker and Docker Compose installed

## Available Templates

### Next.js Business Template

**Technology Stack**: Next.js 14, TypeScript, Tailwind CSS  
**Use Case**: Business websites, SaaS applications, corporate sites  
**Container**: Node.js 22 Alpine with 97% size reduction

**Features**:
- Server-side rendering (SSR)
- Automatic static optimization
- Built-in SEO optimization
- Responsive Tailwind CSS design
- Production-ready performance optimizations

**Ideal For**:
- Business websites
- SaaS applications  
- E-commerce sites
- Marketing pages
- Corporate portals

### Hugo Portfolio Template

**Technology Stack**: Hugo Static Site Generator, Tailwind CSS  
**Use Case**: Personal portfolios, blogs, documentation sites  
**Container**: HugoMods with native Tailwind support

**Features**:
- Lightning-fast static generation
- Markdown content support
- Built-in blog functionality
- Portfolio showcase layouts
- SEO-optimized output

**Ideal For**:
- Personal portfolios
- Technical blogs
- Documentation sites
- Photography portfolios
- Creative showcases

### LAMP WebApp Template

**Technology Stack**: PHP 8.2, Apache, MariaDB 10.11  
**Use Case**: Traditional web applications, CMS installations  
**Container**: Rootless LAMP stack with security enhancements

**Features**:
- Full LAMP stack
- Database integration
- PHP framework support
- Legacy application compatibility
- Secure file permissions

**Ideal For**:
- WordPress sites
- Custom PHP applications
- Legacy web applications
- Database-driven sites
- Traditional web development

## Quick Start

### Deploy a Template Site

The fastest way to deploy a template site:

```bash
# Deploy Next.js business site
./jstack.sh --add-site yourdomain.com --template nextjs-business

# Deploy Hugo portfolio site  
./jstack.sh --add-site portfolio.yourdomain.com --template hugo-portfolio

# Deploy LAMP web application
./jstack.sh --add-site webapp.yourdomain.com --template lamp-webapp
```

### Test Before Deployment

Use dry-run mode to validate before deploying:

```bash
# Test template deployment without making changes
./jstack.sh --add-site test.yourdomain.com --template nextjs-business --dry-run
```

### List Available Templates

See all available templates:

```bash
# List templates with details
cd templates/
ls -la

# Or check template validation tool
bash scripts/lib/template_validation.sh list
```

## Template Deployment

### Step 1: Choose Your Template

Select the template that best matches your needs:

- **Next.js**: Modern web applications with SSR
- **Hugo**: Static sites and blogs  
- **LAMP**: Traditional PHP applications

### Step 2: Prepare Domain

Ensure your domain is configured:

```bash
# Check DNS resolution
dig yourdomain.com

# Verify it points to your server IP
nslookup yourdomain.com
```

### Step 3: Deploy Template

Deploy using the template flag:

```bash
./jstack.sh --add-site yourdomain.com --template template-name
```

The deployment process will:

1. Validate the template
2. Create site directory structure
3. Copy template files
4. Configure environment variables
5. Set up Docker containers
6. Configure NGINX virtual host
7. Request SSL certificates
8. Start services
9. Register site for monitoring

### Step 4: Verify Deployment

Check that your site is running:

```bash
# Check container status
docker ps | grep yourdomain

# Check NGINX configuration
sudo nginx -t

# Test SSL certificate
curl -I https://yourdomain.com

# Check site health
curl https://yourdomain.com/health
```

## Customization

### Customizing Template Content

After deployment, customize your site:

```bash
# Navigate to site directory
cd sites/yourdomain.com/

# Edit source files
cd src/
# Make your changes...

# Rebuild and restart (for Next.js/Hugo)
docker-compose restart
```

### Environment Variables

Modify environment variables:

```bash
# Edit site environment
nano sites/yourdomain.com/.env

# Apply changes
cd sites/yourdomain.com/docker/
docker-compose down
docker-compose up -d
```

### Custom Configuration

Override template configurations:

```bash
# Copy template files to customize
cp -r templates/nextjs-business/ my-custom-site/

# Modify template.json
nano my-custom-site/template.json

# Deploy custom template
./jstack.sh --add-site yourdomain.com my-custom-site/
```

### Database Configuration (LAMP Template)

For LAMP sites with databases:

```bash
# Check database credentials
cat sites/yourdomain.com/.env

# Access database
docker exec -it lamp-database-yourdomain_com mysql -u root -p

# Import database
docker exec -i lamp-database-yourdomain_com mysql -u root -p database_name < backup.sql
```

## Management

### Site Status

Check site status:

```bash
# List all sites
./jstack.sh --list-sites

# Check specific site containers
docker ps --filter "name=yourdomain"

# View site logs
docker logs nextjs-business-yourdomain_com
```

### Updates and Maintenance

Update template sites:

```bash
# Update template files
git pull  # Update COMPASS Stack

# Rebuild containers
cd sites/yourdomain.com/docker/
docker-compose pull
docker-compose up -d --force-recreate
```

### SSL Certificate Renewal

SSL certificates renew automatically, but you can check:

```bash
# Check certificate expiration
sudo certbot certificates

# Manual renewal (if needed)
sudo certbot renew --dry-run
```

### Backups

Template sites are included in COMPASS Stack backups:

```bash
# Create backup including all sites
./jstack.sh --backup template-sites-backup

# Restore specific backup
./jstack.sh --restore template-sites-backup.tar.gz
```

### Site Removal

Remove template sites:

```bash
# Remove site and all associated resources
./jstack.sh --remove-site yourdomain.com

# This will:
# - Stop containers
# - Remove Docker volumes
# - Remove NGINX configuration  
# - Remove SSL certificates
# - Remove from monitoring
```

## Troubleshooting

### Common Issues

**Issue**: Template deployment fails with "Template not found"
```bash
# Solution: Check available templates
ls templates/
# Verify template name spelling
```

**Issue**: SSL certificate request fails
```bash
# Solution: Check domain DNS and email configuration
dig yourdomain.com
cat jstack.config | grep EMAIL
```

**Issue**: Container fails to start
```bash
# Solution: Check container logs
docker logs container-name-yourdomain_com

# Check resource usage
docker stats
```

**Issue**: Site returns 502 Bad Gateway
```bash
# Solution: Check if application container is running
docker ps | grep yourdomain

# Check application logs
docker logs app-container-name

# Verify NGINX upstream configuration
sudo nginx -t
```

### Debug Mode

Enable debug logging for detailed information:

```bash
# Deploy with debug logging
./jstack.sh --add-site yourdomain.com --template nextjs-business --enable-debug

# Check debug logs
tail -f logs/setup_*.log
```

### Template Validation

Validate templates before deployment:

```bash
# Validate specific template
bash scripts/lib/template_validation.sh validate templates/nextjs-business/

# Check template structure
ls -la templates/nextjs-business/
```

### Port Conflicts

If you encounter port conflicts:

```bash
# Check what's using ports
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443

# Stop conflicting services
sudo systemctl stop apache2  # if Apache is running
sudo systemctl stop nginx    # if NGINX is running standalone
```

### DNS Issues

Verify DNS configuration:

```bash
# Check DNS propagation
dig yourdomain.com @8.8.8.8
dig yourdomain.com @1.1.1.1

# Check local resolution
nslookup yourdomain.com

# Test connectivity
ping yourdomain.com
```

### Container Resource Issues

Monitor resource usage:

```bash
# Check container resource usage
docker stats

# Check disk space
df -h

# Check memory usage
free -h

# Clean up unused resources
docker system prune -f
```

### Getting Help

If you need assistance:

1. Check COMPASS Stack logs: `tail -f logs/setup_*.log`
2. Validate template: Use `--dry-run` flag
3. Check Docker status: `docker ps -a`
4. Review NGINX configuration: `sudo nginx -t`
5. Verify DNS: `dig yourdomain.com`

### Advanced Troubleshooting

For complex issues:

```bash
# Generate system report
./jstack.sh --compliance-check

# Check all services status
systemctl status docker
systemctl status nginx
systemctl status ufw

# Review security settings
sudo ufw status
docker info | grep Security
```

Remember: Template deployments follow security best practices and may require proper DNS configuration and firewall settings to function correctly.