# JarvisJR Stack Site Templates

This directory contains pre-configured site templates for rapid deployment within the JarvisJR Stack ecosystem.

## Available Templates

### 1. Next.js Business Template (`nextjs-business/`)
- **Technology Stack**: Next.js 14, TypeScript, Tailwind CSS
- **Container**: Node.js 22 Alpine with 97% size reduction using standalone mode
- **Use Case**: Business websites, SaaS applications, corporate sites
- **Features**: SEO-optimized, responsive design, contact forms, CMS-ready

### 2. Hugo Portfolio Template (`hugo-portfolio/`)
- **Technology Stack**: Hugo Static Site Generator, Tailwind CSS
- **Container**: HugoMods images with native Tailwind CSS support
- **Use Case**: Personal portfolios, blogs, documentation sites
- **Features**: Blazing fast static generation, Markdown content, responsive design

### 3. LAMP WebApp Template (`lamp-webapp/`)
- **Technology Stack**: PHP 8.2, Apache, MariaDB 10.11
- **Container**: Rootless LAMP stack with enhanced security
- **Use Case**: Traditional web applications, CMS installations, dynamic websites
- **Features**: Database integration, PHP frameworks support, legacy compatibility

## Shared Resources (`shared/`)

Common configuration files, utilities, and documentation templates used across all site templates.

## Template Structure

Each template directory contains:
- `template.json` - Template metadata and configuration
- `docker/` - Docker configuration files
- `nginx/` - NGINX configuration templates
- `src/` - Source code and assets
- `docs/` - Template-specific documentation
- `scripts/` - Setup and deployment scripts

## Usage

Deploy a template using the JarvisJR Stack CLI:

```bash
# Deploy with template
./jstack.sh add-site /path/to/your/site --template nextjs-business

# Copy template for customization
cp -r templates/hugo-portfolio/ my-portfolio/
./jstack.sh add-site ./my-portfolio/
```

## Template Development

See `shared/docs/template-development.md` for guidelines on creating custom templates.

## Security & Compliance

All templates follow JarvisJR Stack security standards:
- Rootless container execution
- Network isolation via Docker networks
- Automated SSL certificate management
- Security header configuration
- Compliance monitoring integration