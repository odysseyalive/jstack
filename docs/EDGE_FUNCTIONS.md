# Edge Functions Management in JStack

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Directory Structure](#directory-structure)
4. [Quick Start](#quick-start)
5. [Managing Functions](#managing-functions)
6. [Creating Functions](#creating-functions)
7. [Importing Functions](#importing-functions)
8. [Editing Functions](#editing-functions)
9. [Testing Functions](#testing-functions)
10. [Accessing Functions](#accessing-functions)
11. [Container Management](#container-management)
12. [Troubleshooting](#troubleshooting)
13. [Examples](#examples)
14. [Advanced Topics](#advanced-topics)

---

## Overview

Edge Functions in JStack are TypeScript serverless functions that run on the Deno runtime via Supabase Edge Runtime. They provide HTTP endpoints for custom server-side logic without managing infrastructure.

### Key Features

- **TypeScript** - Full TypeScript support with type safety
- **Deno Runtime** - Modern, secure JavaScript/TypeScript runtime
- **HTTP Endpoints** - Each function gets its own HTTP endpoint
- **Simple Deployment** - Drop files → restart → works
- **Local Development** - Test functions locally before deployment
- **Docker Integration** - Runs in Docker container with volume mounting

### Use Cases

- **Webhooks** - Handle incoming webhooks from third-party services
- **API Endpoints** - Create custom API endpoints
- **Data Processing** - Process data before storing in database
- **Integrations** - Connect to external services
- **Scheduled Tasks** - Run periodic jobs (with external scheduler)
- **Auth Flows** - Custom authentication logic

---

## Architecture

### Docker Container

Edge functions run in the `supabase-functions` Docker container using the `supabase/edge-runtime` image.

```yaml
supabase-functions:
  image: supabase/edge-runtime:v1.62.3
  ports:
    - "9000:9000"
  volumes:
    - ./supabase/functions:/usr/services:ro
  command:
    - start
    - --main-service
    - /usr/services/_main
```

### Volume Mounting

Functions are stored on your host filesystem and mounted into the container:

```
Host: /home/jarvis/jstack/supabase/functions/
                ↓ (volume mount)
Container: /usr/services/
```

**Mount Type:** Read-only (`:ro`)
- Container reads function code from host
- Host is the source of truth
- Changes on host require container restart

### Network Flow

```
Client Request
    ↓
NGINX (Port 80/443)
    ↓
Kong API Gateway
    ↓ /functions/v1/*
supabase-functions Container (Port 9000)
    ↓
Deno Runtime
    ↓
Your Function Code
```

### Environment Variables

The container has access to:
- `JWT_SECRET` - For JWT validation
- `SUPABASE_URL` - Internal Supabase URL
- `SUPABASE_ANON_KEY` - Anonymous key
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key
- `SUPABASE_DB_URL` - Database connection string

---

## Directory Structure

### Standard Layout

```
/home/jarvis/jstack/
└── supabase/
    └── functions/
        ├── _main/              # Main service (required)
        │   └── index.ts
        ├── my-function/        # Your function
        │   ├── index.ts        # Required: Function code
        │   └── deno.json       # Optional: Dependencies
        └── another-function/
            └── index.ts
```

### Function Requirements

Each function directory **must** contain:
- `index.ts` - Main function file

Each function directory **may** contain:
- `deno.json` - Dependency configuration
- `.env` - Environment variables (function-specific)
- Other TypeScript files imported by index.ts

---

## Quick Start

### Create Your First Function

```bash
# Create a new function
./jstack.sh --functions new hello-world

# This creates:
# - Directory: supabase/functions/hello-world/
# - File: supabase/functions/hello-world/index.ts
# - Opens in editor automatically

# Edit the function (if not already open)
./jstack.sh --functions edit hello-world

# Restart container to apply changes
./jstack.sh --functions restart

# Test your function
curl http://localhost:9000/hello-world
```

### Import Existing Function

```bash
# Import from external directory
./jstack.sh --functions import /path/to/my-function

# Function is automatically:
# - Validated (checks for index.ts)
# - Copied to supabase/functions/
# - Made available after container restart
```

### List All Functions

```bash
./jstack.sh --functions list

# Output shows:
# - Function name
# - File count
# - Directory size
# - Whether it has index.ts
# - Whether it has dependencies (deno.json)
```

---

## Managing Functions

### Available Commands

```bash
# List all functions
./jstack.sh --functions list

# Create new function
./jstack.sh --functions new <name>

# Import function from directory
./jstack.sh --functions import <path>

# Edit function
./jstack.sh --functions edit <name>

# Delete function
./jstack.sh --functions delete <name>

# Restart container
./jstack.sh --functions restart

# View logs
./jstack.sh --functions logs [name]
```

### Command Details

#### List Functions

```bash
./jstack.sh --functions list
```

Shows all functions with:
- Function name
- Validation status (✓ or ✗ for index.ts)
- Dependencies status
- File count and total size

#### Create Function

```bash
./jstack.sh --functions new payment-webhook
```

- Creates function directory
- Generates template `index.ts`
- Optionally opens in editor
- No restart needed until you're ready

#### Import Function

```bash
./jstack.sh --functions import /backup/my-function
```

- Validates source has `index.ts`
- Prompts if target exists (overwrite confirmation)
- Copies all files
- Restarts container automatically
- Shows test URL

#### Edit Function

```bash
./jstack.sh --functions edit payment-webhook
```

- Opens `index.ts` in your preferred editor (`$EDITOR`, nano, vim, vi)
- Detects if file was changed
- Validates syntax
- Offers to restart container
- Shows test URL

#### Delete Function

```bash
./jstack.sh --functions delete payment-webhook
```

- Requires confirmation (type 'yes')
- Permanently removes directory
- Restarts container automatically
- Cannot be undone

#### Restart Container

```bash
./jstack.sh --functions restart
```

- Restarts only `supabase-functions` container
- Fast (~2-3 seconds)
- Other services unaffected
- Waits for healthy status

#### View Logs

```bash
# All logs
./jstack.sh --functions logs

# Filter by function name
./jstack.sh --functions logs payment-webhook
```

Shows container logs, optionally filtered by function name.

---

## Creating Functions

### Basic Function Template

```typescript
// supabase/functions/hello/index.ts
Deno.serve(async (req) => {
  return new Response(
    JSON.stringify({ message: "Hello from Edge Function!" }),
    {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      }
    }
  );
});
```

### Function with Request Handling

```typescript
Deno.serve(async (req) => {
  try {
    const { method, url } = req;

    // Handle different HTTP methods
    if (method === 'GET') {
      return new Response(
        JSON.stringify({ message: "GET request received" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    if (method === 'POST') {
      const body = await req.json();

      // Process the data
      const result = {
        received: body,
        processed: true,
        timestamp: new Date().toISOString()
      };

      return new Response(
        JSON.stringify(result),
        {
          headers: { "Content-Type": "application/json" },
          status: 200
        }
      );
    }

    // Method not allowed
    return new Response("Method not allowed", { status: 405 });

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { "Content-Type": "application/json" },
        status: 500
      }
    );
  }
});
```

### Function with Database Access

```typescript
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  try {
    // Create Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Query database
    const { data, error } = await supabase
      .from('users')
      .select('*')
      .limit(10);

    if (error) throw error;

    return new Response(
      JSON.stringify({ data }),
      { headers: { "Content-Type": "application/json" } }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { "Content-Type": "application/json" },
        status: 500
      }
    );
  }
});
```

### Function with Dependencies

Create `deno.json` for dependencies:

```json
{
  "imports": {
    "supabase": "https://esm.sh/@supabase/supabase-js@2",
    "jwt": "https://deno.land/x/djwt@v2.8/mod.ts"
  }
}
```

Then use in `index.ts`:

```typescript
import { createClient } from 'supabase';
import { create } from 'jwt';

Deno.serve(async (req) => {
  // Your code using imported modules
});
```

---

## Importing Functions

### From Local Directory

```bash
# You have functions in a directory
ls /backup/my-functions/
# webhook-handler/
# email-sender/
# cron-job/

# Import one function
./jstack.sh --functions import /backup/my-functions/webhook-handler

# Or manually import all
for func in /backup/my-functions/*; do
  ./jstack.sh --functions import "$func"
done
```

### From Git Repository

```bash
# Clone your functions repository
git clone https://github.com/yourusername/my-functions.git /tmp/my-functions

# Import functions
./jstack.sh --functions import /tmp/my-functions/webhook-handler
./jstack.sh --functions import /tmp/my-functions/email-sender

# Functions are now in supabase/functions/
```

### From Cloud Supabase

**Note:** You cannot automatically download functions from Supabase Cloud. You must have the source code.

**Options:**
1. **From Dashboard:** Copy code from Supabase Dashboard → Edge Functions
2. **From Git:** If you have functions in version control
3. **From Backup:** If you have a local backup

**Manual Process:**
```bash
# Create function directory
mkdir -p /tmp/my-function

# Copy code from Supabase Dashboard
# Paste into index.ts
nano /tmp/my-function/index.ts

# Import to JStack
./jstack.sh --functions import /tmp/my-function
```

---

## Editing Functions

### Using Preferred Editor

```bash
# Edit with default editor
./jstack.sh --functions edit my-function

# Or set your preferred editor
export EDITOR=vim
./jstack.sh --functions edit my-function

# Or use code (VS Code)
export EDITOR=code
./jstack.sh --functions edit my-function
```

### Manual Editing

You can also edit files directly:

```bash
# Edit with your preferred tool
nano supabase/functions/my-function/index.ts

# Or
vim supabase/functions/my-function/index.ts

# Restart container to apply changes
./jstack.sh --functions restart
```

### Auto-Restart on Save

The `edit` command detects file changes and offers to restart:

```bash
./jstack.sh --functions edit my-function
# Make changes...
# Save and exit
# Prompt: "Restart container to apply changes? [Y/n]:"
```

---

## Testing Functions

### Local Testing

```bash
# Test with curl
curl http://localhost:9000/my-function

# Test POST with data
curl -X POST http://localhost:9000/my-function \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'

# Test with authentication
curl http://localhost:9000/my-function \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Using Scripts

Create a test script:

```bash
#!/bin/bash
# test-function.sh

FUNCTION_NAME="my-function"
BASE_URL="http://localhost:9000"

echo "Testing GET request..."
curl -s "${BASE_URL}/${FUNCTION_NAME}" | jq

echo -e "\n\nTesting POST request..."
curl -s -X POST "${BASE_URL}/${FUNCTION_NAME}" \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' | jq
```

### View Logs While Testing

```bash
# Terminal 1: Watch logs
./jstack.sh --functions logs my-function

# Terminal 2: Make requests
curl http://localhost:9000/my-function
```

---

## Accessing Functions

### Local Access

```bash
# Direct access (bypasses Kong/NGINX)
http://localhost:9000/<function-name>

# Example
curl http://localhost:9000/hello-world
```

### Via API Gateway

```bash
# Through Kong API Gateway
http://localhost:8000/functions/v1/<function-name>

# Example
curl http://localhost:8000/functions/v1/hello-world
```

### Public Access

```bash
# Through NGINX with SSL
https://api.yourdomain.com/functions/v1/<function-name>

# Example
curl https://api.example.com/functions/v1/hello-world
```

### Authentication

Functions can access auth tokens from request headers:

```typescript
Deno.serve(async (req) => {
  // Get auth token
  const authHeader = req.headers.get('Authorization');
  const token = authHeader?.replace('Bearer ', '');

  // Validate token with Supabase
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const supabase = createClient(supabaseUrl, supabaseKey, {
    global: {
      headers: { Authorization: `Bearer ${token}` }
    }
  });

  // Get user
  const { data: { user }, error } = await supabase.auth.getUser();

  if (error || !user) {
    return new Response('Unauthorized', { status: 401 });
  }

  // User is authenticated
  return new Response(JSON.stringify({ user }), {
    headers: { 'Content-Type': 'application/json' }
  });
});
```

---

## Container Management

### Manual Container Operations

```bash
# Restart container
docker-compose restart supabase-functions

# View logs
docker logs supabase-functions

# Follow logs
docker logs -f supabase-functions

# Check container status
docker ps | grep supabase-functions

# Inspect container
docker inspect supabase-functions

# Execute command in container
docker exec -it supabase-functions sh
```

### Health Checks

The container runs health checks automatically. Check status:

```bash
# View health status
docker inspect supabase-functions | grep -A 10 '"Health"'

# Or use docker-compose
docker-compose ps supabase-functions
```

### Restart Policy

The container uses `restart: unless-stopped`, meaning:
- Restarts automatically if it crashes
- Does NOT restart if manually stopped
- Starts automatically on system boot

---

## Troubleshooting

### Function Returns 404

**Symptom:** `curl http://localhost:9000/my-function` returns 404

**Causes & Solutions:**

1. **Function doesn't exist**
   ```bash
   ./jstack.sh --functions list
   # Check if function is listed
   ```

2. **Container not restarted**
   ```bash
   ./jstack.sh --functions restart
   # Wait 5 seconds
   curl http://localhost:9000/my-function
   ```

3. **Container not running**
   ```bash
   docker ps | grep supabase-functions
   # If not running:
   docker-compose up -d supabase-functions
   ```

### Function Has Errors

**Symptom:** Function returns 500 or error message

**Debugging:**

1. **Check logs**
   ```bash
   ./jstack.sh --functions logs my-function
   # Look for error messages
   ```

2. **Validate TypeScript**
   ```bash
   # Check syntax manually
   cat supabase/functions/my-function/index.ts
   # Look for syntax errors
   ```

3. **Test minimal function**
   Replace content with minimal test:
   ```typescript
   Deno.serve(() => new Response("OK"));
   ```
   If this works, the issue is in your code.

### Container Won't Start

**Symptom:** Container immediately exits after restart

**Debugging:**

1. **Check container logs**
   ```bash
   docker logs supabase-functions
   # Look for startup errors
   ```

2. **Check Docker Compose config**
   ```bash
   docker-compose config | grep -A 20 "supabase-functions"
   # Verify configuration
   ```

3. **Check volume mount**
   ```bash
   ls -la /home/jarvis/jstack/supabase/functions/
   # Verify directory exists and has functions
   ```

4. **Check _main function**
   ```bash
   ls -la /home/jarvis/jstack/supabase/functions/_main/
   # _main is required by container
   ```

### Permission Issues

**Symptom:** Cannot read/write function files

**Solution:**

```bash
# Fix permissions
sudo chown -R $USER:$USER supabase/functions/
chmod -R 755 supabase/functions/
```

### Port Already in Use

**Symptom:** Port 9000 already in use

**Solution:**

```bash
# Find process using port
sudo lsof -i :9000

# Kill process or change port in docker-compose.yml
```

### Function Works Locally but Not via NGINX

**Causes:**

1. **Kong routing not configured**
   - Check Kong configuration in docker-compose.yml
   - Verify `/functions/v1/*` route exists

2. **NGINX not configured**
   - Check NGINX is forwarding to Kong
   - Check SSL certificates if using HTTPS

3. **Firewall blocking**
   - Check firewall allows traffic on port 443/80

---

## Examples

### Webhook Handler

```typescript
// supabase/functions/webhook-handler/index.ts
Deno.serve(async (req) => {
  try {
    // Verify webhook signature
    const signature = req.headers.get('X-Webhook-Signature');

    if (!signature) {
      return new Response('Missing signature', { status: 401 });
    }

    // Get webhook data
    const payload = await req.json();

    // Process webhook
    console.log('Received webhook:', payload);

    // Store in database
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    await supabase.from('webhook_events').insert({
      payload,
      received_at: new Date().toISOString()
    });

    return new Response(
      JSON.stringify({ status: 'received' }),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Webhook error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 500
      }
    );
  }
});
```

### Email Sender

```typescript
// supabase/functions/send-email/index.ts
Deno.serve(async (req) => {
  try {
    const { to, subject, body } = await req.json();

    // Validate input
    if (!to || !subject || !body) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields' }),
        {
          headers: { 'Content-Type': 'application/json' },
          status: 400
        }
      );
    }

    // Send email (example with SendGrid)
    const SENDGRID_API_KEY = Deno.env.get('SENDGRID_API_KEY');

    const response = await fetch('https://api.sendgrid.com/v3/mail/send', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SENDGRID_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        personalizations: [{ to: [{ email: to }] }],
        from: { email: 'noreply@example.com' },
        subject,
        content: [{ type: 'text/html', value: body }]
      })
    });

    if (!response.ok) {
      throw new Error('Failed to send email');
    }

    return new Response(
      JSON.stringify({ status: 'sent' }),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { 'Content-Type': 'application/json' },
        status: 500
      }
    );
  }
});
```

### CORS-Enabled API

```typescript
// supabase/functions/api/index.ts
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Your API logic
    const data = { message: 'API response' };

    return new Response(
      JSON.stringify(data),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    );

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    );
  }
});
```

---

## Advanced Topics

### Environment Variables

Add function-specific environment variables:

```bash
# In docker-compose.yml, add to supabase-functions service:
environment:
  - CUSTOM_API_KEY=your-key-here
  - CUSTOM_URL=https://api.example.com
```

Then access in function:

```typescript
const apiKey = Deno.env.get('CUSTOM_API_KEY');
const apiUrl = Deno.env.get('CUSTOM_URL');
```

### Shared Code

Create shared utilities:

```
supabase/functions/
├── _shared/
│   ├── utils.ts
│   └── types.ts
├── function-a/
│   └── index.ts
└── function-b/
    └── index.ts
```

Import in functions:

```typescript
import { someUtil } from '../_shared/utils.ts';

Deno.serve(async (req) => {
  const result = someUtil();
  // ...
});
```

### Testing with Deno

Test functions locally with Deno:

```bash
# Install Deno
curl -fsSL https://deno.land/install.sh | sh

# Run function locally
cd supabase/functions/my-function
deno run --allow-net --allow-env index.ts
```

### CI/CD Integration

Add to your CI/CD pipeline:

```yaml
# .github/workflows/deploy-functions.yml
name: Deploy Functions

on:
  push:
    branches: [main]
    paths:
      - 'supabase/functions/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Copy functions to server
        run: |
          scp -r supabase/functions/* user@server:/home/jarvis/jstack/supabase/functions/

      - name: Restart container
        run: |
          ssh user@server 'cd /home/jarvis/jstack && ./jstack.sh --functions restart'
```

---

## Additional Resources

- [Supabase Edge Functions Documentation](https://supabase.com/docs/guides/functions)
- [Deno Documentation](https://deno.land/manual)
- [JStack Main Documentation](../README.md)
- [Migration Guide for Edge Functions](../migration/README.md#edge-functions)

---

## Quick Reference

```bash
# Management
./jstack.sh --functions list              # List all functions
./jstack.sh --functions new <name>        # Create new function
./jstack.sh --functions import <path>     # Import function
./jstack.sh --functions edit <name>       # Edit function
./jstack.sh --functions delete <name>     # Delete function
./jstack.sh --functions restart           # Restart container
./jstack.sh --functions logs [name]       # View logs

# Testing
curl http://localhost:9000/<function-name>               # Local
curl http://localhost:8000/functions/v1/<function-name>  # Via Kong
curl https://api.domain.com/functions/v1/<function-name> # Public

# Manual Operations
docker-compose restart supabase-functions  # Restart
docker logs supabase-functions             # View logs
docker exec -it supabase-functions sh      # Shell access
```

---

**Last Updated:** 2025-01-06
