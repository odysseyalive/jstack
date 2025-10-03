# n8n MCP Proxy - Installation Guide

## Overview

The n8n MCP Proxy enables Claude.ai to interact with your n8n workflows using the Model Context Protocol (MCP). This feature is now **automatically installed** with JStack.

---

## What Gets Installed

When you run `./jstack.sh --install`, the following MCP proxy components are automatically set up:

### 1. MCP Proxy Repository
- **Location:** `/home/jarvis/jstack/n8n-mcp-proxy/`
- **Source:** https://github.com/jacob-dietle/n8n-mcp-sse
- **Cloned during installation**

### 2. Docker Service
- **Service name:** `n8n-mcp-proxy`
- **Port:** 8080 (internal 8000)
- **Added to:** `docker-compose.yml`
- **Auto-starts:** Yes (with `docker-compose up -d`)

### 3. Nginx Configuration
- **Config file:** `nginx/conf.d/mcp.{DOMAIN}.conf`
- **Subdomain:** `mcp.{DOMAIN}` (e.g., mcp.odysseyalive.com)
- **Endpoints:**
  - `/sse` - Server-Sent Events endpoint for Claude.ai
  - `/message` - Message endpoint for MCP protocol
  - `/healthz` - Health check

### 4. SSL Certificate
- **Auto-acquired:** Yes, during installation
- **Domain:** `mcp.{DOMAIN}`
- **Location:** `nginx/certbot/conf/live/mcp.{DOMAIN}/`

### 5. Environment Variables
- **MCP_AUTH_TOKEN** - Generated automatically (32-byte hex)
- **Added to:** `.env` file

---

## Installation Process

### Automatic (Default)

Simply run the standard installation:

```bash
./jstack.sh --install
```

The installation script will:
1. Clone the MCP proxy repository
2. Add the service to docker-compose.yml
3. Generate MCP_AUTH_TOKEN
4. Create nginx configuration
5. Acquire SSL certificate for mcp.{DOMAIN}
6. Build and start the proxy container

### Manual (If Needed)

If you want to set up the MCP proxy separately:

```bash
# Run the MCP proxy setup script
bash scripts/core/setup_mcp_proxy.sh

# Build the proxy container
docker-compose build n8n-mcp-proxy

# Start the proxy
docker-compose up -d n8n-mcp-proxy

# Get SSL certificate (if not already done)
docker-compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --email admin@{DOMAIN} \
  -d mcp.{DOMAIN} \
  --agree-tos

# Reload nginx
docker exec $(docker ps -q -f name=nginx) nginx -s reload
```

---

## DNS Requirements

Before installation, ensure DNS is configured:

```
mcp.{DOMAIN} → Your server IP
```

Example:
```
mcp.odysseyalive.com → 5.78.159.151
```

The installation will check DNS resolution and warn if not configured.

---

## Post-Installation

### Verify Installation

```bash
# Check if proxy is running
docker ps | grep n8n-mcp-proxy

# Test health endpoint
curl https://mcp.{DOMAIN}/healthz
# Expected: "ok"

# Check proxy logs
docker logs jstack_n8n-mcp-proxy_1
```

### Connect Claude.ai

1. Go to: https://claude.ai → Settings → Connectors
2. Click "Add custom connector"
3. Enter:
   - **Name:** `JStack n8n Tools`
   - **URL:** `https://mcp.{DOMAIN}/sse`
4. Enable the connector

### Test Connection

In Claude.ai:
```
What tools do you have available?
```

Claude should list your n8n workflows.

---

## What If Installation Fails?

### MCP Proxy Setup Failed

If the MCP proxy setup encounters issues during installation:

```bash
# Run setup manually
bash scripts/core/setup_mcp_proxy.sh

# Check for errors
docker logs jstack_n8n-mcp-proxy_1
```

### SSL Certificate Failed

If SSL certificate acquisition fails for mcp.{DOMAIN}:

```bash
# Check DNS
dig +short mcp.{DOMAIN}

# Try manual certificate acquisition
docker-compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --email admin@{DOMAIN} \
  -d mcp.{DOMAIN} \
  --agree-tos

# Reload nginx
docker exec $(docker ps -q -f name=nginx) nginx -s reload
```

### Proxy Won't Start

Check environment variables:

```bash
# Verify N8N_API_KEY is set
grep N8N_API_KEY .env

# Verify MCP_AUTH_TOKEN is set
grep MCP_AUTH_TOKEN .env

# Restart the proxy
docker-compose restart n8n-mcp-proxy
```

---

## Configuration

### Environment Variables

The MCP proxy uses these variables (automatically configured):

```env
N8N_API_URL=http://n8n:5678/api/v1
N8N_API_KEY={your-n8n-api-key}
N8N_WEBHOOK_USERNAME=mcp_client
N8N_WEBHOOK_PASSWORD={MCP_AUTH_TOKEN}
DEBUG=false
PORT=8000
```

### Docker Service

Location: `docker-compose.yml`

```yaml
n8n-mcp-proxy:
  build:
    context: ./n8n-mcp-proxy
    dockerfile: Dockerfile
  restart: unless-stopped
  ports:
    - "8080:8000"
  environment:
    - N8N_API_URL=http://n8n:5678/api/v1
    - N8N_API_KEY=${N8N_API_KEY}
    - N8N_WEBHOOK_USERNAME=mcp_client
    - N8N_WEBHOOK_PASSWORD=${MCP_AUTH_TOKEN}
    - DEBUG=false
    - PORT=8000
  depends_on:
    - n8n
```

---

## Upgrading

### Update MCP Proxy

```bash
# Pull latest changes
cd n8n-mcp-proxy
git pull origin main

# Rebuild and restart
cd ..
docker-compose build n8n-mcp-proxy
docker-compose up -d n8n-mcp-proxy
```

### Update JStack Installation Script

If you update JStack and want the latest MCP proxy integration:

```bash
# Re-run setup
bash scripts/core/setup_mcp_proxy.sh
```

---

## Uninstalling

To remove the MCP proxy:

```bash
# Stop and remove container
docker-compose stop n8n-mcp-proxy
docker-compose rm -f n8n-mcp-proxy

# Remove nginx config
rm nginx/conf.d/mcp.{DOMAIN}.conf

# Reload nginx
docker exec $(docker ps -q -f name=nginx) nginx -s reload

# Optionally remove the repository
rm -rf n8n-mcp-proxy
```

Then edit `docker-compose.yml` and remove the `n8n-mcp-proxy` service.

---

## Maintenance

### Logs

```bash
# View proxy logs
docker logs jstack_n8n-mcp-proxy_1 -f

# View nginx access logs for MCP
docker exec $(docker ps -q -f name=nginx) tail -f /var/log/nginx/access.log | grep mcp
```

### Health Monitoring

```bash
# Check health endpoint
curl https://mcp.{DOMAIN}/healthz

# Check if container is running
docker ps | grep mcp-proxy

# Check resource usage
docker stats jstack_n8n-mcp-proxy_1
```

### SSL Certificate Renewal

Certbot automatically renews certificates. To manually renew:

```bash
docker-compose run --rm certbot renew
docker exec $(docker ps -q -f name=nginx) nginx -s reload
```

---

## Troubleshooting

See `ARCHITECTURE_EXPLAINED.md` and `CLAUDE_WORKFLOW_USAGE.md` for:
- How the MCP proxy works
- How to use workflows with Claude.ai
- Common issues and solutions

---

## Summary

✅ **Automatic installation** - No manual setup needed
✅ **SSL included** - Secure HTTPS connection
✅ **Auto-starts** - Runs on system boot
✅ **Health checks** - Easy monitoring
✅ **Nginx configured** - Reverse proxy ready
✅ **Claude.ai ready** - Just add the connector

The MCP proxy is now a standard part of JStack installations!
