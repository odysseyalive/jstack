# Task List: Fix nginx Volume Mount Error in jstack

## Context
The jstack project (AI Second Brain Infrastructure) is experiencing a Docker volume mount error when starting the nginx container. The error indicates a read-only filesystem issue when trying to mount `/home/jarvis/jstack/sites/default/html` to `/usr/share/nginx/html/default`.

## Error Details
```
error mounting "/home/jarvis/jstack/sites/default/html" to rootfs at "/usr/share/nginx/html/default": create mountpoint for /usr/share/nginx/html/default mount: mkdirat /var/lib/docker/overlay2/.../merged/usr/share/nginx/html/default: read-only file system
```

## Tasks to Complete

### 1. Analyze Project Structure
- [ ] Examine the docker-compose.yml file in the jstack repository
- [ ] Identify the nginx service configuration
- [ ] Check the volumes section for the nginx service
- [ ] Note the exact mount paths being used

### 2. Identify Root Causes
- [ ] Determine if `/home/jarvis/jstack/sites/default/html` exists on the host
- [ ] Check if the nginx image expects content at `/usr/share/nginx/html` (standard) or `/usr/share/nginx/html/default` (non-standard)
- [ ] Verify if there are any permission issues with the host directory
- [ ] Check for any conflicting volume mounts or Docker overlay issues

### 3. Create Directory Structure Fix
- [ ] Write a script that creates the necessary directory structure:
  - Create `sites/default/html` directory if it doesn't exist
  - Ensure proper permissions (755) are set
  - Create a default index.html file for testing

### 4. Fix Docker Compose Configuration
- [ ] Modify the nginx volumes section to use the correct mount path
- [ ] Standard nginx expects: `/usr/share/nginx/html` not `/usr/share/nginx/html/default`
- [ ] Ensure the volume mount uses relative paths correctly
- [ ] Add `:ro` flag if the mount should be read-only

### 5. Container Cleanup Tasks
- [ ] Create commands to stop the problematic nginx container
- [ ] Remove the existing nginx container completely
- [ ] Prune any dangling volumes that might cause conflicts
- [ ] Clear Docker overlay2 cache if necessary

### 6. Validation Steps
- [ ] Verify all required directories exist with correct permissions
- [ ] Ensure docker-compose.yml has valid syntax
- [ ] Check that no other services are using ports 80/443
- [ ] Confirm Docker daemon has proper permissions

### 7. Create Recovery Script
- [ ] Combine all fixes into a single executable script
- [ ] Include error handling and status messages
- [ ] Add rollback capability (backup original files)
- [ ] Provide clear next steps for the user

## Expected Outcomes
- The nginx container should start without volume mount errors
- The web server should be accessible on ports 80/443
- All other jstack services (n8n, Supabase, etc.) should continue working
- The fix should be idempotent (safe to run multiple times)

## Additional Considerations
- The fix should work on different Linux distributions
- Should handle both relative and absolute paths
- Must preserve any existing nginx configuration files
- Should not affect other services in the stack (n8n, Supabase, Chrome, Certbot)

## Testing Checklist
- [ ] Run `docker-compose up -d` successfully
- [ ] Verify nginx container is running: `docker ps | grep nginx`
- [ ] Check nginx logs: `docker logs jstack_nginx_1`
- [ ] Access the web interface via browser
- [ ] Ensure SSL/Certbot integration still works