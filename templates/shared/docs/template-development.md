# COMPASS Stack Template Development Guide

This guide explains how to create custom site templates for the COMPASS Stack ecosystem.

## Table of Contents

1. [Template Architecture](#template-architecture)
2. [Creating a New Template](#creating-a-new-template)
3. [Template Configuration](#template-configuration)
4. [Docker Integration](#docker-integration)
5. [NGINX Configuration](#nginx-configuration)
6. [Security Requirements](#security-requirements)
7. [Testing Templates](#testing-templates)
8. [Best Practices](#best-practices)

## Template Architecture

Each COMPASS Stack template follows a standardized directory structure:

```
templates/your-template/
├── template.json                   # Template metadata and configuration
├── docker/                        # Docker configuration
│   ├── Dockerfile                  # Multi-stage build configuration
│   ├── docker-compose.yml          # Service orchestration
│   └── *.conf                     # Service-specific configurations
├── nginx/                         # NGINX configuration
│   └── site.conf.template         # NGINX virtual host template
├── src/                           # Source code and assets
│   ├── (application files)
│   └── package.json               # Dependencies (if applicable)
├── scripts/                       # Template-specific scripts
│   ├── setup.sh                   # Post-installation setup
│   └── health-check.sh           # Health monitoring
└── docs/                          # Template documentation
    ├── README.md                   # Template-specific documentation
    └── deployment.md              # Deployment instructions
```

## Creating a New Template

### Step 1: Initialize Template Directory

```bash
# Create template directory
mkdir -p templates/my-template/{docker,nginx,src,scripts,docs}

# Copy shared template files
cp templates/shared/schema/template.schema.json templates/my-template/
```

### Step 2: Create Template Configuration

Create `template.json` with required metadata:

```json
{
  "name": "My Custom Template",
  "version": "1.0.0",
  "description": "Brief description of your template",
  "type": "static|dynamic|spa|ssr",
  "technology_stack": {
    "primary": "technology-name",
    "runtime": "runtime-environment",
    "database": "database-type",
    "dependencies": ["list", "of", "dependencies"]
  },
  "docker": {
    "image": "base-docker-image",
    "ports": [
      {
        "internal": 3000,
        "protocol": "http",
        "description": "Application port"
      }
    ],
    "security": {
      "user": "non-root-user",
      "read_only": false,
      "no_new_privileges": true
    }
  },
  "nginx": {
    "template": "proxy|static|php|spa",
    "security_headers": true,
    "rate_limiting": {
      "enabled": true,
      "rate": "10r/s",
      "burst": 20
    }
  },
  "compliance": {
    "profile": "default|strict|enterprise",
    "monitoring": true,
    "backup": true
  }
}
```

### Step 3: Create Docker Configuration

**Dockerfile Example:**

```dockerfile
# Multi-stage build for optimization
FROM base-image AS builder
WORKDIR /app
COPY src/ ./
RUN build-commands

FROM base-image AS runner
# Create non-root user for security
RUN addgroup -g 1001 appuser && \
    adduser -S -D -H -u 1001 -g appuser appuser

# Copy built assets
COPY --from=builder --chown=appuser:appuser /app/build ./

# Switch to non-root user
USER appuser

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["start-command"]
```

**Docker Compose Example:**

```yaml
version: '3.8'

services:
  my-template:
    build:
      context: ../
      dockerfile: docker/Dockerfile
    container_name: "my-template-${DOMAIN_SAFE}"
    restart: unless-stopped
    networks:
      - jstack-private
    environment:
      - NODE_ENV=production
      - DOMAIN=${DOMAIN}
    security_opt:
      - no-new-privileges:true
    user: "1001:1001"
    labels:
      - "com.jstack.template=my-template"
      - "com.jstack.version=1.0.0"

networks:
  jstack-private:
    external: true
```

### Step 4: Create NGINX Configuration Template

Create `nginx/site.conf.template`:

```nginx
# NGINX configuration for My Template
upstream my_template_upstream {
    server ${CONTAINER_NAME}:${PORT};
}

# Rate limiting
limit_req_zone $binary_remote_addr zone=my_template_${DOMAIN_SAFE}:10m rate=10r/s;

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # SSL configuration (managed by COMPASS Stack)
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Rate limiting
    limit_req zone=my_template_${DOMAIN_SAFE} burst=20 nodelay;

    # Application proxy
    location / {
        proxy_pass http://my_template_upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$server_name$request_uri;
}
```

## Template Configuration

### Required Fields

- **name**: Human-readable template name
- **version**: Semantic version (e.g., "1.0.0")
- **type**: Site type (static, dynamic, spa, ssr)
- **technology_stack**: Primary technology and dependencies
- **docker**: Container configuration
- **nginx**: Web server configuration

### Optional Fields

- **description**: Template description
- **ssl**: SSL/TLS configuration
- **compliance**: Compliance profile settings
- **setup**: Post-installation commands

### Environment Variables

Templates support automatic environment variable substitution:

- `${DOMAIN}`: Site domain name
- `${DOMAIN_SAFE}`: Domain with safe characters for container names
- `${PROJECT_ROOT}`: COMPASS Stack installation directory
- Custom variables defined in template configuration

## Docker Integration

### Security Requirements

1. **Non-root user**: All containers must run as non-root
2. **Read-only filesystem**: When possible, use read-only containers
3. **No new privileges**: Set `no-new-privileges:true`
4. **Network isolation**: Use `jstack-private` network
5. **Health checks**: Include container health monitoring

### Multi-stage Builds

Use multi-stage builds to minimize image size and security surface:

```dockerfile
# Build stage
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Runtime stage  
FROM node:18-alpine AS runner
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./
USER node
CMD ["npm", "start"]
```

## NGINX Configuration

### Template Variables

Available variables in NGINX templates:

- `${DOMAIN}`: Site domain
- `${DOMAIN_SAFE}`: Safe domain name for configuration
- `${CONTAINER_NAME}`: Docker container name
- `${PORT}`: Application port

### Security Headers

Always include security headers:

```nginx
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
add_header Referrer-Policy "strict-origin-when-cross-origin";
```

### Rate Limiting

Implement rate limiting for protection:

```nginx
limit_req_zone $binary_remote_addr zone=template_${DOMAIN_SAFE}:10m rate=10r/s;
limit_req zone=template_${DOMAIN_SAFE} burst=20 nodelay;
```

## Security Requirements

### Container Security

1. **Rootless execution**: Never run containers as root
2. **Minimal privileges**: Use least-privilege principle
3. **Secure base images**: Use official, minimal base images
4. **Regular updates**: Keep base images and dependencies updated

### Network Security

1. **Internal networks**: Use Docker internal networks
2. **Port restrictions**: Only expose necessary ports
3. **SSL/TLS**: Enforce HTTPS for all traffic
4. **Rate limiting**: Implement request rate limiting

### File System Security

1. **Read-only volumes**: Mount volumes as read-only when possible
2. **Restricted permissions**: Set appropriate file permissions
3. **No sensitive data**: Never include secrets in images
4. **Temporary files**: Clean up temporary files

## Testing Templates

### Validation Command

```bash
# Validate template structure and security
./jstack.sh --add-site test.example.com --template my-template --dry-run
```

### Manual Testing

1. **Structure validation**: Check all required files exist
2. **JSON validation**: Validate template.json against schema
3. **Docker build**: Test Docker image builds successfully
4. **Security scan**: Scan for security vulnerabilities
5. **Integration test**: Deploy and test full functionality

### Automated Testing

Create test scripts in `scripts/test.sh`:

```bash
#!/bin/bash
# Template testing script

set -e

echo "Testing template structure..."
if [[ ! -f "template.json" ]]; then
    echo "ERROR: template.json missing"
    exit 1
fi

echo "Testing Docker build..."
docker build -t test-template -f docker/Dockerfile .

echo "Testing JSON schema..."
jsonschema -i template.json ../shared/schema/template.schema.json

echo "All tests passed!"
```

## Best Practices

### Development

1. **Follow conventions**: Use established naming patterns
2. **Document thoroughly**: Include comprehensive documentation
3. **Version properly**: Use semantic versioning
4. **Test extensively**: Test on multiple environments

### Security

1. **Principle of least privilege**: Minimal permissions
2. **Defense in depth**: Multiple security layers
3. **Regular updates**: Keep dependencies current
4. **Security scanning**: Regular vulnerability assessments

### Performance

1. **Optimize images**: Use multi-stage builds
2. **Cache effectively**: Implement proper caching
3. **Monitor resources**: Include resource monitoring
4. **Health checks**: Implement health monitoring

### Maintenance

1. **Clear documentation**: Maintain updated docs
2. **Version control**: Track all changes
3. **Backup strategies**: Include backup procedures
4. **Update procedures**: Document update processes

## Template Submission

When contributing templates to COMPASS Stack:

1. **Follow guidelines**: Adhere to all development guidelines
2. **Complete documentation**: Include all required documentation
3. **Pass validation**: Ensure template passes all validation tests
4. **Security review**: Submit for security review
5. **Testing**: Provide comprehensive test cases

## Support

For template development support:

- Review existing templates for examples
- Check validation errors with `--dry-run` flag
- Consult COMPASS Stack documentation
- Test thoroughly before deployment

Remember: Security and compliance are paramount in template development. Always follow established patterns and security requirements.