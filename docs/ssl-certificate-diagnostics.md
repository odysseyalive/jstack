# Certificate Symlink Diagnosis Guide

## Issue
The `enable_https_redirects.sh` script reports "No certificate found" even though certificates were successfully acquired by certbot. The certificates appear as broken symlinks on the host filesystem.

## Understanding the Problem

Certbot stores certificates in two locations:
- **Archive**: `/etc/letsencrypt/archive/{domain}/` - Actual certificate files (fullchain1.pem, privkey1.pem, etc.)
- **Live**: `/etc/letsencrypt/live/{domain}/` - Symlinks pointing to the archive files

When the script runs on the **host**, it checks:
- Host path: `./nginx/certbot/conf/live/api.odysseyalive.com/fullchain.pem`
- This is a symlink: `fullchain.pem -> ../../archive/api.odysseyalive.com/fullchain1.pem`
- The symlink is relative, so it looks for: `./nginx/certbot/conf/archive/api.odysseyalive.com/fullchain1.pem`

## Diagnostic Steps

### Step 1: Verify Certificate Directories Exist

```bash
cd ~/jstack

# Check what's in the certbot conf directory
ls -la nginx/certbot/conf/

# Expected output should include:
# - accounts/
# - archive/
# - live/
# - renewal/
```

### Step 2: Check Archive Directory

```bash
# List archive directory
ls -la nginx/certbot/conf/archive/

# Check specific subdomain archive
ls -la nginx/certbot/conf/archive/api.odysseyalive.com/

# Expected files:
# - cert1.pem
# - chain1.pem
# - fullchain1.pem
# - privkey1.pem
```

### Step 3: Test Symlink Resolution

```bash
# Test if symlink can be followed
readlink -f nginx/certbot/conf/live/api.odysseyalive.com/fullchain.pem

# Test if the target file exists
test -f nginx/certbot/conf/live/api.odysseyalive.com/fullchain.pem && echo "EXISTS" || echo "BROKEN"

# Check what the symlink points to
ls -l nginx/certbot/conf/live/api.odysseyalive.com/fullchain.pem
```

### Step 4: Compare Container vs Host

```bash
# Check what's inside the certbot container
docker-compose run --rm --entrypoint="" certbot ls -la /etc/letsencrypt/archive/

# Copy archive from container to verify structure
docker cp jstack_certbot_1:/etc/letsencrypt/archive /tmp/certbot-archive-check
ls -la /tmp/certbot-archive-check/
```

### Step 5: Check Volume Mount Configuration

```bash
# Verify docker-compose volume mounts
grep -A 5 "certbot:" docker-compose.yml | grep -A 3 "volumes:"

# Expected:
# - ./nginx/certbot/conf:/etc/letsencrypt
# - ./nginx/certbot/www:/var/www/certbot
```

## Common Issues and Solutions

### Issue 1: Archive Directory Missing on Host

**Symptom**: `nginx/certbot/conf/archive/` doesn't exist

**Cause**: Certbot wrote to container-only volume instead of bind mount

**Solution**:
```bash
# Copy archive from container to host
docker cp jstack_certbot_1:/etc/letsencrypt/archive nginx/certbot/conf/
docker cp jstack_certbot_1:/etc/letsencrypt/renewal nginx/certbot/conf/

# Fix permissions
sudo chown -R jarvis:jarvis nginx/certbot/conf/archive
sudo chown -R jarvis:jarvis nginx/certbot/conf/renewal
chmod -R 755 nginx/certbot/conf/archive
chmod -R 755 nginx/certbot/conf/renewal
```

### Issue 2: Symlinks Point to Wrong Path

**Symptom**: Symlinks exist but `readlink -f` returns empty or wrong path

**Cause**: Symlinks created with container paths instead of relative paths

**Solution**: Recreate symlinks with correct paths
```bash
cd nginx/certbot/conf/live/api.odysseyalive.com/

# Remove broken symlinks
rm fullchain.pem privkey.pem cert.pem chain.pem

# Create correct symlinks
ln -s ../../archive/api.odysseyalive.com/fullchain1.pem fullchain.pem
ln -s ../../archive/api.odysseyalive.com/privkey1.pem privkey.pem
ln -s ../../archive/api.odysseyalive.com/cert1.pem cert.pem
ln -s ../../archive/api.odysseyalive.com/chain1.pem chain.pem
```

### Issue 3: Permission Issues

**Symptom**: Archive directory owned by root, script can't read

**Cause**: Certbot runs as root, creates files with root ownership

**Solution**: Fix ownership while preserving security
```bash
# Check current ownership
ls -la nginx/certbot/conf/archive/

# Fix ownership (run as user with sudo)
sudo chown -R jarvis:jarvis nginx/certbot/conf/archive
sudo chown -R jarvis:jarvis nginx/certbot/conf/live

# Set proper permissions
chmod -R 755 nginx/certbot/conf/archive
chmod -R 755 nginx/certbot/conf/live
```

## Verification

After applying fixes, verify the certificate check works:

```bash
cd ~/jstack

# Test the certificate check function manually
cert_dir="nginx/certbot/conf/live/api.odysseyalive.com"
test -f "$cert_dir/fullchain.pem" && echo "✓ Certificate found" || echo "✗ Certificate NOT found"

# Run the HTTPS redirect script
bash scripts/core/enable_https_redirects.sh

# Expected output:
# [timestamp] ✓ Certificate found for api.odysseyalive.com - enabling HTTPS
# [timestamp] ✓ Certificate found for studio.odysseyalive.com - enabling HTTPS
# [timestamp] ✓ Certificate found for n8n.odysseyalive.com - enabling HTTPS
# [timestamp] ✓ Certificate found for chrome.odysseyalive.com - enabling HTTPS
```

## Next Steps

Once certificates are properly detected:

```bash
# Reload nginx to apply HTTPS configuration
docker-compose exec nginx nginx -s reload

# Verify HTTPS is working
curl -I https://api.odysseyalive.com
curl -I https://studio.odysseyalive.com
curl -I https://n8n.odysseyalive.com
curl -I https://chrome.odysseyalive.com
```

## Reference: Volume Mount Structure

```
Host Filesystem:                Container Filesystem:
~/jstack/nginx/certbot/conf  →  /etc/letsencrypt
├── accounts/                   ├── accounts/
├── archive/                    ├── archive/
│   └── api.odysseyalive.com/   │   └── api.odysseyalive.com/
│       ├── cert1.pem           │       ├── cert1.pem
│       ├── chain1.pem          │       ├── chain1.pem
│       ├── fullchain1.pem      │       ├── fullchain1.pem
│       └── privkey1.pem        │       └── privkey1.pem
├── live/                       ├── live/
│   └── api.odysseyalive.com/   │   └── api.odysseyalive.com/
│       ├── fullchain.pem →     │       ├── fullchain.pem →
│       └── privkey.pem →       │       └── privkey.pem →
└── renewal/                    └── renewal/
```

The symlinks in `live/` use relative paths (`../../archive/`) so they work the same on both host and container.
