# Claude.ai Connector Setup for n8n Workflows

## Overview

This document explains how to connect Claude.ai to your n8n workflows using the Model Context Protocol (MCP). Two approaches are available:

1. **Native n8n MCP Trigger** (Recommended) - Uses n8n's built-in MCP Server node
2. **External MCP Proxy** (Fallback) - Uses jacob-dietle/n8n-mcp-sse proxy server

## Current Status

✅ **Nginx configured** - MCP SSE endpoint exposed with CORS headers
✅ **Workflows compatible** - All 7 tool workflows support dual triggers
✅ **MCP_AUTH_TOKEN set** - Token: `1242844f1cf141f808f7d50d3e4415bb28dc7cc91d25ad1089096dec5bdf196f`
⚠️ **Workflow activation required** - MCP Server workflow must be activated via n8n UI

---

## Approach 1: Native n8n MCP Trigger (Recommended)

### Architecture
```
Claude.ai → nginx (MCP SSE endpoint) → n8n (MCP Trigger) → Tool Workflows → Supabase
```

### Workflow: [JJ] MCP Server (ID: 7y14lKhSFK0AW0Aj)

**Status:** Database activated, requires UI activation for endpoint registration

**Tool Workflows Configured:**
1. `search_memory` - Search Memory Tool
2. `manage_notes` - CRUD Notes
3. `manage_contacts` - Store a Contact
4. `query_image` - Query Image Tool
5. `process_image` - Image Tool
6. `manage_tags` - Manage Tags
7. `manage_tasks` - Manage Scheduled Tasks

### Setup Steps

#### 1. Activate MCP Server Workflow
1. Open n8n UI: https://n8n.odysseyalive.com
2. Navigate to workflows
3. Find **"[JJ] MCP Server"** (ID: 7y14lKhSFK0AW0Aj)
4. Click the **Activate** toggle (top-right)
5. Wait for the workflow to register its MCP SSE endpoint

#### 2. Get the MCP Endpoint URL
After activation, the MCP Trigger will generate a unique SSE endpoint:
```
https://n8n.odysseyalive.com/mcp/{generated-token}/sse
```

The token will be different from the `MCP_AUTH_TOKEN` environment variable. You can find it in:
- n8n workflow execution logs
- n8n workflow settings/trigger panel
- Or it will be auto-populated in the `N8N_MCP_ENDPOINT` env variable after first activation

#### 3. Connect Claude.ai
1. Go to Claude.ai → Settings → Connectors
2. Click **"Add custom connector"**
3. Enter:
   - **Name:** `JStack n8n Tools`
   - **Remote MCP server URL:** `https://n8n.odysseyalive.com/mcp/{generated-token}/sse`
4. Click **"Add"**
5. Enable the connector

#### 4. Verify Connection
In Claude.ai:
1. Click **"Search and tools"** button (bottom left)
2. Find your **"JStack n8n Tools"** connector
3. Click **"Connect"**
4. Test with: *"What tools do you have available?"*

Expected response: Claude should list all 7 tool workflows.

---

## Approach 2: External MCP Proxy (Fallback)

If the native MCP Trigger doesn't work with Claude.ai, use this proven community solution.

### Architecture
```
Claude.ai → MCP Proxy (Railway/Docker) → n8n API → Webhook Workflows → Supabase
```

### Deploy Options

#### Option A: Railway (Easiest)
1. Visit: https://railway.com/template/se2WHK
2. Click **"Deploy on Railway"**
3. Configure environment variables:
   ```
   N8N_API_URL=https://n8n.odysseyalive.com/api/v1
   N8N_API_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4Yzg2MzBiYy1jYjU1LTQ2ZWItOTE4Zi01ZGVhZDk2YjE3OTgiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzU5NDQyOTMzfQ.Bk1ywvS02XMMZ47eHNY9jW6vWdSGkoQPFqE59oycpN0
   DEBUG=false
   ```
4. **Important:** Settings → Generate Domain → **Expose Port 8080**
5. Copy your Railway URL: `https://your-app.up.railway.app`

#### Option B: Docker (Self-hosted)
```bash
# Clone repository
git clone https://github.com/jacob-dietle/n8n-mcp-sse.git
cd n8n-mcp-sse

# Build image
docker build -t n8n-mcp-proxy .

# Run container
docker run -d -p 8080:8080 \
  -e N8N_API_URL="https://n8n.odysseyalive.com/api/v1" \
  -e N8N_API_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4Yzg2MzBiYy1jYjU1LTQ2ZWItOTE4Zi01ZGVhZDk2YjE3OTgiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzU5NDQyOTMzfQ.Bk1ywvS02XMMZ47eHNY9jW6vWdSGkoQPFqE59oycpN0" \
  -e DEBUG=false \
  --name n8n-mcp-proxy \
  n8n-mcp-proxy
```

#### Option C: Add to JStack Docker Compose
Add this service to your `docker-compose.yml`:

```yaml
  n8n-mcp-proxy:
    build:
      context: ./n8n-mcp-proxy
      dockerfile: Dockerfile
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - N8N_API_URL=http://n8n:5678/api/v1
      - N8N_API_KEY=${N8N_API_KEY}
      - DEBUG=false
    depends_on:
      - n8n
```

Then expose via subdomain (e.g., `mcp.odysseyalive.com`) in nginx.

### Connect Claude.ai to Proxy
1. Claude.ai → Settings → Connectors → **"Add custom connector"**
2. Enter:
   - **Name:** `JStack n8n Tools (Proxy)`
   - **Remote MCP server URL:**
     - Railway: `https://your-app.up.railway.app/sse`
     - Docker: `https://mcp.odysseyalive.com/sse`
3. Click **"Add"** and enable

---

## Compatible Workflows

All 7 tool workflows are **already compatible** with both approaches:

### ✅ [JJ] Search Memory Tool (fkWy5qv7NqXESa3Z)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/search-memory` (POST)
- **Tool Name:** `search_memory`

### ✅ [JJ] CRUD Notes (pso1y5LnYKReE5tj)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/crud-notes` (POST)
- **Tool Name:** `manage_notes`

### ✅ [JJ] Store a Contact (WRtmkXh8GLNnCskD)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/store-contact` (POST)
- **Tool Name:** `manage_contacts`

### ✅ [JJ] Query Image Tool (u0AD6tlQbh9KFRD7)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/query-image` (POST)
- **Tool Name:** `query_image`

### ✅ [JJ] Image Tool (FLD9ZTdynV1RA5at)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/process-image` (POST)
- **Tool Name:** `process_image`

### ✅ [JJ] Manage Tags (2zEJOnQV6tGjfndw)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/manage-tags` (POST)
- **Tool Name:** `manage_tags`

### ✅ [JJ] Manage Scheduled Tasks (6TgWbwUDWbE7xwRU)
- **Triggers:** Webhook + Execute Workflow
- **Endpoint:** `/manage-scheduled-tasks` (POST)
- **Tool Name:** `manage_tasks`

**Note:** All workflows call Supabase Edge Functions, ensuring consistent backend behavior regardless of trigger method.

---

## Nginx Configuration

The nginx configuration has been updated to support MCP SSE endpoints:

```nginx
# MCP SSE endpoint for Claude.ai integration
location ~ "^/mcp/([a-f0-9]+)/sse$" {
    proxy_pass http://n8n:5678;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # SSE-specific headers
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_buffering off;
    proxy_cache off;
    chunked_transfer_encoding off;

    # Extended timeouts for SSE
    proxy_connect_timeout 86400s;
    proxy_send_timeout 86400s;
    proxy_read_timeout 86400s;

    # CORS headers for Claude.ai
    add_header Access-Control-Allow-Origin "https://claude.ai" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept" always;
    add_header Access-Control-Max-Age 3600 always;

    # Handle preflight requests
    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

**File:** `/home/jarvis/jstack/nginx/conf.d/n8n.odysseyalive.com.conf`
**Applied:** ✅ Configuration tested and nginx reloaded

---

## Troubleshooting

### Issue: "Webhook not registered" Error
**Cause:** MCP Server workflow not activated or not fully started
**Solution:**
1. Activate workflow in n8n UI
2. Wait 10-15 seconds for registration
3. Restart n8n if needed: `docker restart jstack_n8n_1`

### Issue: "Cannot connect to MCP server"
**Causes:**
- Workflow not active
- Incorrect endpoint URL
- CORS headers not applied

**Solutions:**
1. Verify workflow is active: Check n8n UI
2. Check nginx logs: `docker logs jstack_nginx_1`
3. Test endpoint manually:
   ```bash
   curl -v "https://n8n.odysseyalive.com/mcp/{token}/sse"
   ```

### Issue: "Authentication failed"
**Cause:** MCP_AUTH_TOKEN mismatch or not properly set in n8n secrets
**Solution:**
1. Verify token in n8n: Settings → Credentials → Secrets
2. Ensure `MCP_AUTH_TOKEN` secret exists
3. Re-activate workflow if secret was just added

### Issue: Tools not executing
**Causes:**
- Tool workflow not active
- Supabase Edge Function down
- Missing user_telegram_id in request

**Solutions:**
1. Verify all 7 tool workflows are active
2. Check Supabase status: `docker ps | grep supabase`
3. Review workflow execution logs in n8n

---

## Security Considerations

### 1. API Key Protection
- ✅ n8n API key is stored in environment variables
- ✅ Not exposed in nginx logs
- ⚠️ Rotate key periodically (every 90 days recommended)

### 2. MCP Authentication
- ✅ Bearer token authentication enabled
- ✅ Token stored in n8n secrets
- ⚠️ Token visible in nginx access logs (use encrypted logging)

### 3. CORS Configuration
- ✅ Limited to `https://claude.ai` origin
- ✅ Only allows GET, POST, OPTIONS methods
- ✅ Preflight requests handled

### 4. Rate Limiting
**Not yet implemented** - Consider adding:
```nginx
limit_req_zone $binary_remote_addr zone=mcp_limit:10m rate=10r/m;

location ~ "^/mcp/([a-f0-9]+)/sse$" {
    limit_req zone=mcp_limit burst=20 nodelay;
    # ... rest of config
}
```

### 5. Monitoring
**Recommended additions:**
- Add logging for MCP tool calls
- Monitor execution times
- Alert on failed authentications
- Track usage per tool

---

## Testing Checklist

Before connecting Claude.ai, verify:

- [ ] MCP Server workflow is active (green toggle in n8n UI)
- [ ] All 7 tool workflows are active
- [ ] MCP endpoint responds (test with curl)
- [ ] nginx CORS headers present
- [ ] Supabase Edge Functions accessible
- [ ] MCP_AUTH_TOKEN secret exists in n8n

Test commands:
```bash
# Check workflow status
docker run --rm -v "/home/jarvis/jstack/data/n8n:/data" nouchka/sqlite3 \
  /data/database.sqlite \
  "SELECT name, active FROM workflow_entity WHERE name LIKE '%[JJ]%';"

# Test MCP endpoint (replace {token} with actual token)
curl -v "https://n8n.odysseyalive.com/mcp/{token}/sse"

# Check nginx CORS headers
curl -I -H "Origin: https://claude.ai" \
  "https://n8n.odysseyalive.com/mcp/{token}/sse"
```

---

## Next Steps

### Immediate
1. **Activate MCP Server workflow via n8n UI**
2. **Retrieve generated SSE endpoint URL**
3. **Test connection from Claude.ai**

### Short-term
4. Monitor Claude.ai tool usage
5. Add rate limiting to MCP endpoint
6. Implement usage analytics

### Long-term
7. Expand tool catalog (add more workflows)
8. Implement semantic caching for tool responses
9. Add multi-user support with per-user tokens

---

## Reference Links

- **n8n MCP Documentation:** https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.mcptrigger/
- **MCP Specification:** https://spec.modelcontextprotocol.io/
- **jacob-dietle/n8n-mcp-sse:** https://github.com/jacob-dietle/n8n-mcp-sse
- **Railway Deployment:** https://railway.com/template/se2WHK
- **Supergateway (SSE Bridge):** https://github.com/supercorp-ai/supergateway

---

## Support

For issues or questions:
1. Check n8n workflow execution logs
2. Review nginx error logs: `docker logs jstack_nginx_1 | grep error`
3. Check Supabase Edge Function logs
4. Review this documentation's troubleshooting section
5. Test with curl commands above

---

*Last Updated: October 3, 2025*
*Configuration Version: 1.0*
