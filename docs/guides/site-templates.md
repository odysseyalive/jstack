# 🌐 Site Templates Guide

> Deploy production-ready websites in minutes with pre-configured templates

## Overview

JarvisJR Stack includes three production-ready site templates that integrate seamlessly with your existing infrastructure:

- **🚀 [Next.js Business](#nextjs-business-template)** - Modern React applications with server-side rendering
- **📝 [Hugo Portfolio](#hugo-portfolio-template)** - Lightning-fast static sites with Tailwind CSS  
- **💼 [LAMP WebApp](#lamp-webapp-template)** - PHP applications with MariaDB database

All templates include:
- ✅ **Automatic SSL certificates**
- ✅ **NGINX reverse proxy integration** 
- ✅ **Security compliance monitoring**
- ✅ **Docker containerization**
- ✅ **Production optimizations**

---

## Quick Start

### 1. Choose Your Template

| Template | Best For | Tech Stack | Deploy Time |
|----------|----------|------------|-------------|
| **nextjs-business** | Business sites, web apps | Next.js, React, Node.js | ~3 minutes |
| **hugo-portfolio** | Blogs, portfolios, docs | Hugo, Tailwind CSS | ~2 minutes |
| **lamp-webapp** | PHP applications, CMSs | PHP, Apache, MariaDB | ~4 minutes |

### 2. Deploy in One Command

```bash
# Basic deployment (uses default configuration):
./jstack.sh --add-site yourdomain.com --template nextjs-business

# Or copy and customize first:
cp -r templates/nextjs-business/ ~/my-site/
# Edit ~/my-site/site.json and other configs
./jstack.sh --add-site yourdomain.com --template ~/my-site/
```

### 3. Access Your New Site

Once deployed, your site will be available at:
- **🌐 Your Site**: `https://yourdomain.com`
- **🔒 SSL Certificate**: Automatically configured
- **📊 Monitoring**: Integrated with JarvisJR compliance dashboard

---

## Templates Deep Dive

### Next.js Business Template

**Perfect for**: Business websites, web applications, e-commerce

**Features**:
- Next.js 14 with App Router
- TypeScript configuration
- Tailwind CSS integration
- Production optimizations (97% size reduction)
- Built-in API routes support

**Directory Structure**:
```
templates/nextjs-business/
├── site.json              # Site configuration
├── docker-compose.yml     # Container orchestration
├── Dockerfile             # Multi-stage Node.js build
├── src/                   # Next.js application source
├── docs/                  # Template documentation
└── scripts/               # Build and deployment scripts
```

**Customization**:
- Edit `site.json` for basic settings (domain, SSL, environment)
- Modify `src/` directory for your application code
- Update `docker-compose.yml` for advanced configuration

**[📚 Detailed Next.js Guide →](site-templates/nextjs-guide.md)**

---

### Hugo Portfolio Template

**Perfect for**: Blogs, portfolios, documentation sites, marketing sites

**Features**:
- Hugo static site generator
- Native Tailwind CSS integration
- Lightning-fast builds (<30 seconds)
- SEO-optimized output
- CDN-ready static files

**Directory Structure**:
```
templates/hugo-portfolio/
├── site.json              # Site configuration
├── docker-compose.yml     # Hugo build container
├── config.toml            # Hugo configuration
├── content/               # Markdown content
├── themes/                # Hugo theme
└── static/                # Static assets
```

**Customization**:
- Edit `config.toml` for site settings
- Add content in `content/` directory (Markdown files)
- Customize theme in `themes/` directory

**[📚 Detailed Hugo Guide →](site-templates/hugo-guide.md)**

---

### LAMP WebApp Template

**Perfect for**: PHP applications, WordPress, custom web applications

**Features**:
- PHP 8.2 with Apache
- MariaDB 10.11 database
- Modern PHP configuration
- Database initialization scripts
- Multi-container orchestration

**Directory Structure**:
```
templates/lamp-webapp/
├── site.json              # Site configuration
├── docker-compose.yml     # Multi-container setup
├── web/                   # PHP application files
├── database/              # SQL initialization scripts
├── config/                # Apache and PHP configuration
└── backups/               # Database backup scripts
```

**Customization**:
- Place PHP application in `web/` directory
- Add database schema in `database/init.sql`
- Configure PHP settings in `config/php.ini`

**[📚 Detailed LAMP Guide →](site-templates/lamp-guide.md)**

---

## Advanced Usage

### Custom Site Configuration

Every template includes a `site.json` file for customization:

```json
{
  "domain": "example.com",
  "template": "nextjs-business",
  "ssl": {
    "enabled": true,
    "force_https": true
  },
  "resources": {
    "memory_limit": "512m",
    "cpu_limit": "0.5"
  },
  "environment": {
    "NODE_ENV": "production",
    "DATABASE_URL": "auto-generated"
  },
  "compliance_profile": "default"
}
```

### Multiple Site Management

```bash
# List all deployed sites:
./jstack.sh --list-sites

# Deploy multiple sites:
./jstack.sh --add-site app.company.com --template nextjs-business
./jstack.sh --add-site blog.company.com --template hugo-portfolio
./jstack.sh --add-site admin.company.com --template lamp-webapp

# Remove a site:
./jstack.sh --remove-site old-site.com
```

### Template Validation

Before deployment, validate your template:

```bash
# Test template without deploying:
./jstack.sh --add-site test.com --template nextjs-business --dry-run

# Validate template structure:
./jstack.sh --validate-template templates/nextjs-business/
```

---

## Integration with JarvisJR

### NGINX Reverse Proxy

All templates automatically integrate with JarvisJR's NGINX setup:
- SSL termination and certificate management
- Security headers and rate limiting
- Compression and caching
- WebSocket support (for Next.js and real-time apps)

### Database Integration

Templates can access JarvisJR's PostgreSQL database:
- Connection details auto-injected via environment variables
- Supabase API access for modern applications
- Database Studio access for management

### Monitoring and Compliance

All deployed sites include:
- Security compliance monitoring (SOC2, GDPR, ISO 27001)
- Performance monitoring and alerts
- Automated backup integration
- Log aggregation and analysis

---

## Troubleshooting

### Common Issues

**Site not loading after deployment**:
```bash
# Check container status:
docker ps | grep your-domain

# View container logs:
docker logs container-name

# Test NGINX configuration:
./jstack.sh --test-nginx your-domain.com
```

**SSL certificate issues**:
```bash
# Regenerate certificates:
./jstack.sh --renew-ssl your-domain.com

# Check certificate status:
./jstack.sh --ssl-status your-domain.com
```

**Template deployment failed**:
```bash
# Run with verbose output:
./jstack.sh --add-site your-domain.com --template nextjs-business --verbose

# Check template validation:
./jstack.sh --validate-template templates/nextjs-business/
```

### Getting Help

- **📋 [Common Issues →](troubleshooting.md#site-templates)**
- **💬 [Community Forum](https://www.skool.com/ai-productivity-hub)**
- **🐛 [Report Bug](https://github.com/your-repo/issues)**

---

## Next Steps

1. **📚 [Template-Specific Guides](site-templates/)** - Detailed documentation for each template
2. **⚙️ [Advanced Configuration](configuration.md#site-templates)** - Customize templates further
3. **🔒 [Security Best Practices](../reference/security.md#site-security)** - Secure your deployed sites
4. **📊 [Monitoring Setup](../reference/monitoring.md)** - Monitor site performance
5. **🔄 [Backup Strategy](backup-recovery.md#site-backups)** - Protect your site data

---

**Need a custom template?** Check out our [Template Development Guide](../reference/template-development.md) to create your own.