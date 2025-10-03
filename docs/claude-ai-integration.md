# Claude.ai Integration Guide

Complete guide for integrating Claude.ai with your JStack n8n workflows via the Model Context Protocol (MCP).

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Architecture](#architecture)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [Troubleshooting](#troubleshooting)
7. [Security](#security)

---

## Overview

JStack automatically sets up an MCP proxy that allows Claude.ai to interact with your n8n workflows. This integration:

- ✅ **Automatic Installation** - Included in `./jstack.sh --install`
- ✅ **Secure by Default** - Hash-based URL path for obscurity
- ✅ **SSL/HTTPS** - Automatic certificate management
- ✅ **Production Ready** - Nginx reverse proxy with proper CORS headers

### What Gets Installed

| Component | Location | Description |
|-----------|----------|-------------|
| MCP Proxy Source | `n8n-mcp-proxy/` | jacob-dietle/n8n-mcp-sse repository |
| Docker Service | `docker-compose.yml` | Auto-starts on boot |
| Nginx Config | `nginx/conf.d/mcp.{DOMAIN}.conf` | Reverse proxy with SSL |
| SSL Certificate | `nginx/certbot/conf/live/mcp.{DOMAIN}/` | Auto-acquired via Let's Encrypt |
| Auth Token | `.env` (MCP_AUTH_TOKEN) | Auto-generated |
| URL Hash | `.env` (MCP_URL_HASH) | Security through obscurity |

---

## Quick Start

### New Installation

```bash
./jstack.sh --install
```

The MCP proxy is automatically:
1. Cloned from GitHub
2. Added to docker-compose.yml
3. Configured with nginx
4. SSL certificate acquired
5. Started with Docker

### Connect Claude.ai

After installation:

1. Go to https://claude.ai → Settings → Connectors
2. Add custom connector:
   - **Name:** `JStack n8n Tools`
   - **URL:** `https://mcp.{YOUR_DOMAIN}/{HASH}/sse`
3. Enable and test

The secure URL will be displayed at the end of installation. You can also find the hash in your `.env` file:

```bash
grep MCP_URL_HASH .env
```

Then construct the URL:
```
https://mcp.{YOUR_DOMAIN}/{MCP_URL_HASH}/sse
```

### Verify Installation

```bash
# Check if proxy is running
docker ps | grep mcp-proxy

# Test health endpoint
curl https://mcp.{YOUR_DOMAIN}/healthz
# Expected: "ok"

# View logs
docker logs jstack_n8n-mcp-proxy_1
```

---

## Architecture

### How It Works

```
Claude.ai
  ↓ HTTPS + MCP Protocol
https://mcp.{DOMAIN}/{HASH}/sse
  ↓ nginx (SSL + CORS + URL rewrite)
n8n-mcp-proxy:8000 (Docker)
  ↓ REST API
n8n:5678/api/v1
  ↓ Webhook Calls
Your n8n Workflows
  ↓ HTTP/HTTPS
Supabase Edge Functions
```

### Why External Proxy Instead of Native MCP?

JStack uses the [jacob-dietle/n8n-mcp-sse](https://github.com/jacob-dietle/n8n-mcp-sse) external proxy instead of n8n's native MCP Trigger node because:

1. **n8n's native MCP Trigger doesn't work with Claude.ai** - The native implementation was tested and failed to establish proper connections
2. **External proxy is proven** - Community-tested solution that works reliably with Claude.ai connectors
3. **Better control** - Allows for security features like hash-based URLs and custom CORS handling
4. **Webhook compatibility** - Your workflows use webhook triggers, which work perfectly with the proxy's `run_webhook` tool

### URL Path Security

The nginx configuration uses **both** hash-protected and standard paths:

**Hash-Protected (Entry Point)**:
- `/{HASH}/sse` - Initial SSE connection from Claude.ai
- `/{HASH}/message` - Optional hash-protected message endpoint

**Standard Paths (Protocol Callbacks)**:
- `/sse` - Used by MCP protocol for callbacks
- `/message` - Used by MCP protocol for message passing

The nginx rewrite rules strip the hash prefix before forwarding to the MCP proxy:

```nginx
location /{HASH}/sse {
    rewrite ^/{HASH}(/sse.*)$ $1 break;
    proxy_pass http://n8n-mcp-proxy:8000;
    # ... headers and CORS ...
}
```

This approach:
- ✅ Obscures the entry point (requires knowing the hash)
- ✅ Maintains MCP protocol compatibility
- ✅ Allows proper callback handling

---

## Configuration

### Environment Variables

The MCP proxy uses these variables (automatically configured during installation):

```env
# In .env file
N8N_API_KEY={your-n8n-api-key}
MCP_AUTH_TOKEN={auto-generated-32-byte-hex}
MCP_URL_HASH={auto-generated-16-byte-hex}
```

### Docker Service Configuration

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

### Nginx Configuration

Location: `nginx/conf.d/mcp.{DOMAIN}.conf`

Key features:
- **Dual endpoints**: Hash-protected + standard paths
- **CORS headers**: Configured for `https://claude.ai`
- **SSE support**: Proper headers for Server-Sent Events
- **Extended timeouts**: 24-hour connections for SSE
- **URL rewriting**: Strips hash prefix before proxying

---

## Usage

### Available Tools in Claude.ai

When connected, Claude.ai can see your n8n workflows as tools. The proxy exposes:

1. **get_workflow** - Get details about a specific workflow
2. **list_workflows** - List all available workflows
3. **run_webhook** - Execute a workflow via its webhook trigger ⭐ **(Use this one!)**
4. **execution_run** - Execute a workflow via n8n API (won't work for webhook-based workflows)

### Executing Workflows from Claude.ai

Your workflows use **webhook triggers**, so you must use the `run_webhook` tool:

#### Example Conversation

```
User: Store this contact - Francis Rupert, email francis@odysseyalive.com

Claude: I'll store that contact for you.

[Claude calls run_webhook tool]
Tool: store-contact
Webhook Data: {
  "name": "Francis Rupert",
  "email": "francis@odysseyalive.com"
}

✅ Contact stored successfully
```

### Workflow Data Formats

#### Store Contact
```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "phone": "+1234567890",
  "company": "Acme Inc"
}
```

#### Store Message
```json
{
  "sender": "John Doe",
  "content": "Meeting notes from today",
  "metadata": {
    "channel": "email",
    "timestamp": "2025-10-03T10:30:00Z"
  }
}
```

#### Store Note
```json
{
  "title": "Project Ideas",
  "content": "1. Build new feature\n2. Refactor codebase",
  "tags": ["ideas", "projects"]
}
```

#### Process Image
```json
{
  "image_url": "https://example.com/image.jpg",
  "operation": "analyze"
}
```

#### Store Image
```json
{
  "image_url": "https://example.com/photo.jpg",
  "caption": "Team photo from conference",
  "tags": ["team", "conference", "2025"]
}
```

#### Manage Tags
```json
{
  "action": "add",
  "resource_type": "note",
  "resource_id": "123",
  "tags": ["important", "review"]
}
```

#### Test Connection
```json
{
  "service": "supabase"
}
```

---

## Troubleshooting

### Proxy Not Running

```bash
# Check status
docker ps | grep mcp-proxy

# View logs
docker logs jstack_n8n-mcp-proxy_1

# Restart
docker-compose restart n8n-mcp-proxy
```

### Can't Connect from Claude.ai

**Check the URL is correct:**
```bash
# Get your hash
grep MCP_URL_HASH .env

# Test endpoint
curl https://mcp.{YOUR_DOMAIN}/{HASH}/sse
```

**Verify nginx config:**
```bash
docker exec $(docker ps -q -f name=nginx) nginx -t
```

**Check nginx logs:**
```bash
docker exec $(docker ps -q -f name=nginx) tail -50 /var/log/nginx/error.log
```

**Reload nginx:**
```bash
docker exec $(docker ps -q -f name=nginx) nginx -s reload
```

### SSL Certificate Issues

```bash
# Check DNS
dig +short mcp.{YOUR_DOMAIN}

# Manually acquire certificate
docker-compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d mcp.{YOUR_DOMAIN} \
  --agree-tos

# Reload nginx
docker exec $(docker ps -q -f name=nginx) nginx -s reload
```

### Workflows Not Executing

**Check if using correct tool:**
- ✅ Use `run_webhook` for workflows with webhook triggers
- ❌ Don't use `execution_run` (won't work with webhooks)

**Check workflow is active:**
```bash
# View n8n logs
docker logs jstack_n8n_1 -f
```

**Verify webhook URL is accessible:**
- Your workflows call Supabase Edge Functions
- Make sure those endpoints are working

### Connection Drops Immediately

**Check CORS headers:**
- Nginx must allow `https://claude.ai` origin
- Configuration includes this by default

**Check nginx is forwarding correctly:**
```bash
# Check nginx access logs
docker exec $(docker ps -q -f name=nginx) tail -f /var/log/nginx/access.log | grep mcp
```

**Verify both hash and standard paths work:**
```bash
# Hash path (entry point)
curl -I https://mcp.{YOUR_DOMAIN}/{HASH}/sse

# Standard path (callbacks)
curl -I https://mcp.{YOUR_DOMAIN}/sse
```

Both should return successful responses (not 404).

---

## Security

### URL Hash Protection

The MCP endpoint uses a randomly-generated hash in the URL path:

```
https://mcp.{DOMAIN}/d43e0d46b774a8d480819051a5fca471/sse
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                     32-character random hex hash
```

**Security through obscurity:**
- Makes endpoint harder to discover via scanning
- Doesn't replace authentication (MCP proxy handles auth)
- Hash is stored in `.env` as `MCP_URL_HASH`

**To regenerate the hash:**
```bash
# Generate new hash
openssl rand -hex 16

# Update .env
# Edit MCP_URL_HASH in .env file

# Update nginx config
# Edit nginx/conf.d/mcp.{DOMAIN}.conf
# Replace old hash with new hash in location directives

# Reload nginx
docker exec $(docker ps -q -f name=nginx) nginx -s reload

# Update Claude.ai connector with new URL
```

### HTTPS/SSL

All connections are encrypted via HTTPS:
- SSL certificates auto-acquired via Let's Encrypt
- Certificates auto-renewed by certbot
- Nginx handles SSL termination

### CORS Protection

Nginx CORS headers restrict access to Claude.ai:

```nginx
add_header Access-Control-Allow-Origin "https://claude.ai" always;
```

### Network Isolation

The MCP proxy runs in Docker network:
- Only exposed ports: 8080 (proxied by nginx)
- Direct access blocked by firewall
- All traffic goes through nginx reverse proxy

### Authentication

The MCP proxy uses basic authentication:
- Username: `mcp_client`
- Password: `${MCP_AUTH_TOKEN}` (from .env)
- Token auto-generated during installation

### Monitoring

```bash
# Watch for suspicious activity
docker logs jstack_n8n-mcp-proxy_1 -f

# Monitor nginx access
docker exec $(docker ps -q -f name=nginx) tail -f /var/log/nginx/access.log | grep mcp

# Check resource usage
docker stats jstack_n8n-mcp-proxy_1
```

---

## Manual Setup (Advanced)

If you need to set up the MCP proxy separately:

```bash
# Run setup script
bash scripts/core/setup_mcp_proxy.sh

# Build and start
docker-compose build n8n-mcp-proxy
docker-compose up -d n8n-mcp-proxy

# Get SSL certificate (if not already done)
docker-compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  --email admin@{DOMAIN} \
  -d mcp.{DOMAIN} \
  --agree-tos

# Reload nginx
docker exec $(docker ps -q -f name=nginx) nginx -s reload

# Test
curl https://mcp.{DOMAIN}/healthz
```

---

## Upgrading

### Update MCP Proxy

```bash
cd n8n-mcp-proxy
git pull origin main
cd ..
docker-compose build n8n-mcp-proxy
docker-compose up -d n8n-mcp-proxy
```

### Update JStack Integration

If JStack updates the MCP integration:

```bash
# Re-run setup (won't overwrite existing config)
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

# Remove from docker-compose.yml manually
# (edit file and remove n8n-mcp-proxy service)
```

---

## Additional Resources

- **MCP Proxy Repository**: https://github.com/jacob-dietle/n8n-mcp-sse
- **Model Context Protocol**: https://modelcontextprotocol.io/
- **Claude.ai Connectors**: https://claude.ai/settings/connectors
- **n8n Documentation**: https://docs.n8n.io/

---

## Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs: `docker logs jstack_n8n-mcp-proxy_1`
3. Check nginx logs: `docker exec $(docker ps -q -f name=nginx) tail -50 /var/log/nginx/error.log`
4. Verify configuration: `docker exec $(docker ps -q -f name=nginx) nginx -t`

---

## Summary

✅ **Zero configuration** - Automatic setup during installation
✅ **Secure by default** - Hash-based URLs + SSL certificates
✅ **Production ready** - Nginx reverse proxy with CORS
✅ **Well documented** - Complete setup and usage guides
✅ **Easy to maintain** - Standard Docker service

The MCP proxy is now a first-class feature of JStack!
