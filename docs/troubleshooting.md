# Troubleshooting Guide

When things go wrong, don't panic. Most JStack issues have simple fixes. Work through these steps systematically.

## Quick Diagnostic Commands

Start here when something isn't working:

```bash
# Check overall system status
./jstack.sh status

# Run full diagnostics
./jstack.sh diagnostics

# Validate your configuration
./jstack.sh validate

# Preview what dry-run would do
./jstack.sh --dry-run
```

## Common Issues & Solutions

### "Cannot access Docker" Error

**Symptoms:** 
```
Error: Cannot access Docker. Ensure:
  1. Docker service is running
  2. User is in docker group
```

**Solutions:**
```bash
# Check if Docker is running
sudo systemctl status docker

# Start Docker if stopped
sudo systemctl start docker

# Add user to docker group
sudo usermod -aG docker $USER

# Apply group membership without logout
newgrp docker

# Test Docker access
docker ps
```

### Services Won't Start

**Check what's wrong:**
```bash
# See which containers are running
docker-compose ps

# Check logs for errors
docker-compose logs

# Check specific service
docker-compose logs nginx
docker-compose logs n8n
docker-compose logs supabase-db
```

**Common fixes:**
```bash
# Port already in use
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443
# Kill process using the port or change config

# Restart everything
./jstack.sh restart

# Rebuild containers
docker-compose down
docker-compose up -d --build
```

### SSL Certificate Issues

**Symptoms:** Browser shows "Not Secure" or certificate errors

**Check certificates:**
```bash
# List certificates
ls -la nginx/ssl/

# Check certificate expiry
openssl x509 -in nginx/ssl/live/yourdomain.com/cert.pem -text -noout | grep "Not After"

# Test SSL configuration
docker-compose exec nginx nginx -t
```

**Fix certificates:**
```bash
# Regenerate self-signed for testing
bash scripts/core/ssl_cert.sh generate_self_signed yourdomain.com admin@yourdomain.com

# Get real Let's Encrypt certificate
bash scripts/core/setup_ssl_certbot.sh yourdomain.com

# Restart NGINX after cert changes
docker-compose restart nginx
```

### Can't Access n8n or Supabase

**Check service URLs:**
- n8n: `https://n8n.yourdomain.com`
- Supabase: `https://studio.yourdomain.com`

**Verify DNS and domains:**
```bash
# Check if domain resolves to your server
nslookup n8n.yourdomain.com
dig yourdomain.com

# Check NGINX routing
docker-compose exec nginx cat /etc/nginx/conf.d/n8n.yourdomain.com.conf
```

**Reset credentials:**
```bash
# Check current environment
grep N8N_BASIC_AUTH docker-compose.yml

# Set new credentials
export N8N_BASIC_AUTH_USER="newuser"
export N8N_BASIC_AUTH_PASSWORD="newpass"
docker-compose up -d n8n
```

### Database Connection Errors

**Check database status:**
```bash
# Is database running?
docker-compose ps supabase-db

# Can we connect?
docker-compose exec supabase-db pg_isready

# Check database logs
docker-compose logs supabase-db
```

**Fix database issues:**
```bash
# Restart database
docker-compose restart supabase-db

# Check disk space (common cause)
df -h

# Restore from backup if corrupted
./jstack.sh --restore backup-filename.tar.gz
```

### Permission Issues

**Symptoms:** Services can't read/write files, permission denied errors

**Fix permissions:**
```bash
# Fix all workspace permissions
./scripts/core/fix_workspace_permissions.sh

# Check current ownership
ls -la data/
ls -la nginx/

# Manual fix if needed
sudo chown -R $USER:docker data/
sudo chown -R $USER:docker nginx/
sudo chmod -R 755 data/
```

### Out of Disk Space

**Check disk usage:**
```bash
# Overall disk space
df -h

# Docker space usage
docker system df

# Large files in project
du -sh data/* nginx/* logs/*
```

**Free up space:**
```bash
# Clean Docker unused data
docker system prune -a

# Remove old logs
find logs/ -name "*.log" -mtime +30 -delete

# Clean old backups
ls -la backups/
# Delete old ones manually
```

### NGINX Configuration Errors

**Test configuration:**
```bash
# Check NGINX syntax
docker-compose exec nginx nginx -t

# View NGINX error log
docker-compose logs nginx | grep error

# Check configuration files
ls -la nginx/conf.d/
```

**Fix common NGINX issues:**
```bash
# Syntax error in config
# Edit the problematic .conf file in nginx/conf.d/

# Restart after fixing
docker-compose restart nginx

# Reset to default if needed
cp nginx/conf.d/default.conf nginx/conf.d/yourdomain.com.conf
# Edit with your domain name
```

### Chrome/Puppeteer Issues

**Check Chrome service:**
```bash
# Is Chrome running?
docker-compose ps chrome

# Check Chrome logs
docker-compose logs chrome

# Restart Chrome
docker-compose restart chrome
```

### n8n Workflow Problems

**Common workflow issues:**
- **Credentials:** Check connection settings in n8n interface
- **Timeouts:** Increase timeout values in workflow settings  
- **Memory:** Restart n8n if workflows are complex
- **Database connections:** Verify Supabase credentials

**Reset n8n:**
```bash
# Restart n8n service
docker-compose restart n8n

# Clear n8n cache (stops all workflows temporarily)
docker-compose exec n8n rm -rf /home/node/.n8n/cache
docker-compose restart n8n
```

## System Resource Issues

### High CPU Usage
```bash
# Check which container is using CPU
docker stats

# Check system load
top
htop
```

### High Memory Usage
```bash
# Container memory usage
docker stats --no-stream

# System memory
free -h

# Kill memory-heavy processes if needed
docker-compose restart [service-name]
```

### Network Issues
```bash
# Check open ports
sudo netstat -tlnp

# Test internal container communication
docker-compose exec n8n ping supabase-db
docker-compose exec n8n ping chrome

# Check Docker networks
docker network ls
docker network inspect jstack_default
```

## Recovery Procedures

### Complete System Reset
```bash
# Nuclear option - starts fresh (keeps your data)
./jstack.sh down
docker system prune -a
./jstack.sh --install
```

### Restore from Backup
```bash
# List available backups
ls -la backups/

# Restore specific backup
./jstack.sh --restore backups/backup-2024-01-15.tar.gz
```

### Rebuild Single Service
```bash
# Rebuild just one problematic service
docker-compose stop n8n
docker-compose rm n8n
docker-compose up -d n8n
```

## Getting Help

### Collect Diagnostic Information
```bash
# Save system info for support
./jstack.sh diagnostics > diagnostic-output.txt

# Include Docker info
docker version >> diagnostic-output.txt
docker-compose version >> diagnostic-output.txt

# Include recent logs
docker-compose logs --tail=100 >> diagnostic-output.txt
```

### Check JStack Logs
```bash
# Installation logs
cat logs/install.log

# Service-specific logs
docker-compose logs [service-name]

# System logs
journalctl -u docker
```

### Before Asking for Help

1. **Run diagnostics:** `./jstack.sh diagnostics`
2. **Check logs:** `docker-compose logs`
3. **Try dry-run:** `./jstack.sh --dry-run`
4. **Document the error:** Copy exact error messages
5. **Note what changed:** What were you doing when it broke?

## Prevention Tips

**Regular maintenance:**
```bash
# Weekly health check
./jstack.sh status
./jstack.sh validate

# Monthly cleanup
docker system prune
./jstack.sh --backup

# Keep configs backed up
cp -r nginx/conf.d/ backups/nginx-configs-$(date +%Y%m%d)/
```

**Monitor disk space:**
```bash
# Add to crontab for weekly checks
echo "0 0 * * 0 df -h | mail -s 'Disk Space Report' you@domain.com" | crontab -
```

Remember: Most issues are temporary. Work through the steps methodically, and your JStack will be running smoothly again.