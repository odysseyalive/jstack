# Troubleshooting Guide

When things go wrong, don't panic. Most JStack issues have simple fixes. Work through these steps systematically.

## Quick Diagnostic Commands
- Check overall system status
```bash
./jstack.sh status
```
- Run full diagnostics
```bash
./jstack.sh diagnostics
```
- Validate your configuration
```bash
./jstack.sh validate
```
- Preview dry-run
```bash
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
- Check if Docker is running
```bash
sudo systemctl status docker
```
- Start Docker if stopped
```bash
sudo systemctl start docker
```
- Add user to docker group
```bash
sudo usermod -aG docker $USER
```
- Apply group membership without logout
```bash
newgrp docker
```
- Test Docker access
```bash
docker ps
```

### Services Won't Start
- See which containers are running
```bash
docker-compose ps
```
- Check logs for errors
```bash
docker-compose logs
```
- Check specific service logs
```bash
docker-compose logs nginx
```
```bash
docker-compose logs n8n
```
```bash
docker-compose logs supabase-db
```
**Common fixes:**
- Port already in use
```bash
sudo netstat -tlnp | grep :80
```
```bash
sudo netstat -tlnp | grep :443
```
- Restart everything
```bash
./jstack.sh restart
```
- Rebuild containers
```bash
docker-compose down
```
```bash
docker-compose up -d --build
```

### SSL Certificate Issues
- List certificates
```bash
ls -la nginx/ssl/
```
- Check certificate expiry
```bash
openssl x509 -in nginx/ssl/live/yourdomain.com/cert.pem -text -noout | grep "Not After"
```
- Test SSL configuration
```bash
docker-compose exec nginx nginx -t
```
**Fix certificates:**
- Regenerate self-signed for testing
```bash
bash scripts/core/ssl_cert.sh generate_self_signed yourdomain.com admin@yourdomain.com
```
- Get real Let's Encrypt certificate
```bash
bash scripts/core/setup_ssl_certbot.sh yourdomain.com
```
- Restart NGINX after cert changes
```bash
docker-compose restart nginx
```

**Advanced certificate diagnostics:**
For detailed troubleshooting of certificate symlink issues, permission problems, and volume mount verification, see the [SSL Certificate Diagnostics Guide](ssl-certificate-diagnostics.md).

### Can't Access n8n or Supabase
- Check service URLs:
  - n8n: `https://n8n.yourdomain.com`
  - Supabase: `https://studio.yourdomain.com`
- Check if domain resolves to your server
```bash
nslookup n8n.yourdomain.com
```
```bash
dig yourdomain.com
```
- Check NGINX routing
```bash
docker-compose exec nginx cat /etc/nginx/conf.d/n8n.yourdomain.com.conf
```
**Reset credentials:**
- Check current environment
```bash
grep N8N_BASIC_AUTH docker-compose.yml
```
- Set new credentials
```bash
export N8N_BASIC_AUTH_USER="newuser"
```
```bash
export N8N_BASIC_AUTH_PASSWORD="newpass"
```
```bash
docker-compose up -d n8n
```

### Database Connection Errors
- Is database running?
```bash
docker-compose ps supabase-db
```
- Can we connect?
```bash
docker-compose exec supabase-db pg_isready
```
- Check database logs
```bash
docker-compose logs supabase-db
```
**Fix database issues:**
- Restart database
```bash
docker-compose restart supabase-db
```
- Check disk space (common cause)
```bash
df -h
```
- Restore from backup if corrupted
```bash
./jstack.sh --restore backup-filename.tar.gz
```

### Permission Issues
**Symptoms:** Services can't read/write files, permission denied errors
- Fix all workspace permissions
```bash
./scripts/core/fix_workspace_permissions.sh
```
- Check current ownership
```bash
ls -la data/
```
```bash
ls -la nginx/
```
- Manual fix if needed
```bash
sudo chown -R $USER:docker data/
```
```bash
sudo chown -R $USER:docker nginx/
```
```bash
sudo chmod -R 755 data/
```

### Out of Disk Space
- Check disk usage (overall)
```bash
df -h
```
- Docker space usage
```bash
docker system df
```
- Large files in project
```bash
du -sh data/* nginx/* logs/*
```
- Clean Docker unused data
```bash
docker system prune -a
```
- Remove old logs
```bash
find logs/ -name "*.log" -mtime +30 -delete
```
- Clean old backups
```bash
ls -la backups/
```
# Delete old ones manually as needed

### NGINX Configuration Errors
- Check NGINX syntax
```bash
docker-compose exec nginx nginx -t
```
- View NGINX error log
```bash
docker-compose logs nginx | grep error
```
- Check configuration files
```bash
ls -la nginx/conf.d/
```
**Fix common NGINX issues:**
- Edit the problematic .conf file in nginx/conf.d/
- Restart after fixing
```bash
docker-compose restart nginx
```
- Reset to default if needed
```bash
cp nginx/conf.d/default.conf nginx/conf.d/yourdomain.com.conf
```
# Edit with your domain name as needed

### Chrome/Puppeteer Issues
- Is Chrome running?
```bash
docker-compose ps chrome
```
- Check Chrome logs
```bash
docker-compose logs chrome
```
- Restart Chrome
```bash
docker-compose restart chrome
```

### n8n Workflow Problems
**Common workflow issues:**
- Check connection settings in n8n interface
- Increase timeout values in workflow settings
- Restart n8n if workflows are complex
- Verify Supabase credentials
- Restart n8n service
```bash
docker-compose restart n8n
```
- Clear n8n cache (stops all workflows temporarily)
```bash
docker-compose exec n8n rm -rf /home/node/.n8n/cache
```
```bash
docker-compose restart n8n
```

### System Resource Issues
- Check which container is using CPU
```bash
docker stats
```
- Check system load
```bash
top
```
```bash
htop
```
- Container memory usage
```bash
docker stats --no-stream
```
- System memory
```bash
free -h
```
- Kill memory-heavy processes if needed
```bash
docker-compose restart [service-name]
```
- Check open ports
```bash
sudo netstat -tlnp
```
- Test internal container communication
```bash
docker-compose exec n8n ping supabase-db
```
```bash
docker-compose exec n8n ping chrome
```
- Check Docker networks
```bash
docker network ls
```
```bash
docker network inspect jstack_default
```

## Recovery Procedures

- Complete system reset
```bash
./jstack.sh down
```
```bash
docker system prune -a
```
```bash
./jstack.sh --install
```
- Restore from backup
```bash
ls -la backups/
```
```bash
./jstack.sh --restore backups/backup-2024-01-15.tar.gz
```
- Rebuild single service
```bash
docker-compose stop n8n
```
```bash
docker-compose rm n8n
```
```bash
docker-compose up -d n8n
```

## Getting Help
- Save system info for support
```bash
./jstack.sh diagnostics > diagnostic-output.txt
```
- Include Docker info
```bash
docker version >> diagnostic-output.txt
```
```bash
docker-compose version >> diagnostic-output.txt
```
- Include recent logs
```bash
docker-compose logs --tail=100 >> diagnostic-output.txt
```
- Check JStack logs
```bash
cat logs/install.log
```
- Service-specific logs
```bash
docker-compose logs [service-name]
```
- System logs
```bash
journalctl -u docker
```

### Before Asking for Help
1. Run diagnostics: `./jstack.sh diagnostics`
2. Check logs: `docker-compose logs`
3. Try dry-run: `./jstack.sh --dry-run`
4. Document the error: Copy exact error messages
5. Note what changed: What were you doing when it broke?

## Prevention Tips
- Weekly health check
```bash
./jstack.sh status
```
```bash
./jstack.sh validate
```
- Monthly cleanup
```bash
docker system prune
```
```bash
./jstack.sh --backup
```
- Keep configs backed up
```bash
cp -r nginx/conf.d/ backups/nginx-configs-$(date +%Y%m%d)/
```
- Monitor disk space weekly
```bash
echo "0 0 * * 0 df -h | mail -s 'Disk Space Report' you@domain.com" | crontab -
```

Most issues are temporary. Work through the steps methodically, and your JStack will be running smoothly again.