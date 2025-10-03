# MCP Server Setup - Step by Step Instructions

## Current Status

✅ **Infrastructure Ready:**
- Nginx configured for MCP SSE endpoint
- CORS headers enabled
- All 7 tool workflows active and compatible

⚠️ **Action Required:**
- Import and activate MCP Server workflow

---

## Option 1: Import MCP Server Workflow (Recommended)

### Step 1: Access n8n UI
1. Go to: https://n8n.odysseyalive.com
2. Login with your credentials

### Step 2: Import Workflow
1. Click **"+"** (top right) → **"Import from File"**
2. Upload: `/home/jarvis/jstack/n8n-workflows/mcp-server.json`
   - Or use the workflow definition below

### Step 3: Verify MCP_AUTH_TOKEN Secret
1. In n8n, go to **Settings** → **Credentials**
2. Ensure secret `MCP_AUTH_TOKEN` exists with value:
   ```
   1242844f1cf141f808f7d50d3e4415bb28dc7cc91d25ad1089096dec5bdf196f
   ```

### Step 4: Activate Workflow
1. Open the imported **"[JJ] MCP Server"** workflow
2. Click the **Activate** toggle (top-right)
3. Wait 5-10 seconds for the MCP endpoint to register

### Step 5: Get MCP Endpoint URL
The MCP Trigger will expose an SSE endpoint at:
```
https://n8n.odysseyalive.com/mcp/{auto-generated-token}/sse
```

To find the token:
1. Open the workflow in n8n
2. Click on the **"MCP Server Trigger"** node
3. Look for the endpoint URL in the node info panel
4. Or check workflow execution logs after first activation

---

## Option 2: Create MCP Server Workflow Manually

If import doesn't work, create the workflow manually:

### Step 1: Create New Workflow
1. In n8n, click **"+"** → **"New workflow"**
2. Name it: **"[JJ] MCP Server"**

### Step 2: Add MCP Server Trigger Node
1. Click **"Add first step"**
2. Search for: **"MCP Server Trigger"**
3. Add the node

### Step 3: Configure MCP Server Trigger
In the node settings, add these tool workflows:

| Tool Name | Workflow Name | Description |
|-----------|--------------|-------------|
| `search_memory` | [JJ] Search Memory Tool | Search through stored messages, notes, contacts, and images using semantic or keyword search |
| `manage_notes` | [JJ] CRUD Notes | Create, read, update, or delete notes with support for tags and metadata |
| `manage_contacts` | [JJ] Store a Contact | Store or search contacts with detailed information including name, phone, email, company |
| `query_image` | [JJ] Query Image Tool | Ask questions about previously stored images by providing image ID and your question |
| `process_image` | [JJ] Image Tool | Process and store new images with AI-generated descriptions |
| `manage_tags` | [JJ] Manage Tags | Add, remove, or list tags for notes and contacts to organize content |
| `manage_tasks` | [JJ] Manage Scheduled Tasks | Create, list, update, or complete scheduled tasks and reminders |

**Configuration:**
- **Authentication:** Bearer Token
- **Bearer Token:** `={{ $secrets.MCP_AUTH_TOKEN }}`

### Step 4: Add No Operation Node
1. Connect a **"No Operation"** node after the MCP Server Trigger
2. This is just to complete the workflow

### Step 5: Activate
1. Click **Save**
2. Click **Activate** toggle

---

## Option 3: Use Existing Workflow (Quick Fix)

Since there's already an activated workflow in the database (ID: 7y14lKhSFK0AW0Aj), you can access it directly:

### Via URL:
```
https://n8n.odysseyalive.com/workflow/7y14lKhSFK0AW0Aj
```

**Note:** This workflow is currently unarchived and active. If it doesn't appear in the UI, try:
1. Refresh the browser
2. Clear browser cache
3. Check the "Archived" workflows section

---

## Option 4: Use External MCP Proxy (Fallback)

If the MCP Trigger approach doesn't work, deploy an external proxy:

### Quick Deploy to Railway:
1. Visit: https://railway.com/template/se2WHK
2. Configure:
   ```
   N8N_API_URL=https://n8n.odysseyalive.com/api/v1
   N8N_API_KEY=<your-api-key>
   DEBUG=false
   ```
3. Deploy and get your URL
4. Use: `https://your-app.up.railway.app/sse` in Claude.ai

This approach bypasses the MCP Trigger entirely and uses webhooks directly.

---

## Verification Steps

After activating the MCP Server workflow:

### 1. Check Workflow Status
```bash
docker run --rm -v "/home/jarvis/jstack/data/n8n:/data" nouchka/sqlite3 \
  /data/database.sqlite \
  "SELECT name, active, isArchived FROM workflow_entity WHERE name LIKE '%MCP%';"
```

Expected: One workflow with `active=1` and `isArchived=0`

### 2. Test MCP Endpoint
```bash
curl -v "https://n8n.odysseyalive.com/mcp/{token}/sse"
```

Expected: SSE stream or MCP protocol response (not 404)

### 3. Check n8n Logs
```bash
docker logs jstack_n8n_1 --tail 50 | grep -i mcp
```

Look for: "MCP trigger registered" or similar messages

---

## Connect Claude.ai

Once the MCP endpoint is active:

1. **Claude.ai** → Settings → Connectors
2. **Add custom connector**
3. Enter:
   - **Name:** `JStack n8n Tools`
   - **URL:** `https://n8n.odysseyalive.com/mcp/{token}/sse`
4. **Add** and **Enable** the connector

### Test the Connection
In Claude.ai, try:
- "What tools do you have available?"
- "Search my memory for notes about meetings"
- "List all my contacts"

Expected: Claude should list all 7 tools and be able to execute them.

---

## Troubleshooting

### Issue: Can't find workflow in UI
**Try:**
1. Direct URL: `https://n8n.odysseyalive.com/workflow/7y14lKhSFK0AW0Aj`
2. Check archived workflows
3. Create new workflow (Option 2 above)

### Issue: MCP_AUTH_TOKEN not found
**Fix:**
1. n8n → Settings → Credentials → Add new secret
2. Name: `MCP_AUTH_TOKEN`
3. Value: `1242844f1cf141f808f7d50d3e4415bb28dc7cc91d25ad1089096dec5bdf196f`

### Issue: Workflow active but endpoint returns 404
**Cause:** MCP Trigger hasn't registered its endpoint yet
**Fix:**
1. Deactivate workflow
2. Wait 5 seconds
3. Re-activate workflow
4. Check n8n logs for registration message

### Issue: Tool workflows not found
**Verify all 7 workflows are active:**
```bash
docker run --rm -v "/home/jarvis/jstack/data/n8n:/data" nouchka/sqlite3 \
  /data/database.sqlite \
  "SELECT name, active FROM workflow_entity WHERE name LIKE '[JJ]%' AND name NOT LIKE '%MCP%';"
```

All should show `active=1`

---

## Summary

**Quickest Path:**
1. Access: https://n8n.odysseyalive.com/workflow/7y14lKhSFK0AW0Aj
2. Click Activate (if not already active)
3. Get MCP endpoint URL from trigger node
4. Add to Claude.ai connectors

**If that doesn't work:**
1. Create new workflow manually (Option 2)
2. Or deploy external proxy (Option 4)

**All infrastructure is ready** - just need the workflow activated and the endpoint URL!

---

*See `claude-ai-connector-setup.md` for complete documentation*
