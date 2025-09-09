# 🆘 JarvisJR Stack Troubleshooting Guide

> **Quick Fix First**: Try `./jstack.sh --diagnose` to get instant diagnostic information for most issues.

## 🚨 Emergency Quick Fixes

If your JarvisJR Stack isn't working, try these commands in order:

```bash
# 1. Check overall system status
./jstack.sh --diagnose basic

# 2. Restart all services
docker restart $(docker ps -aq)

# 3. Check DNS and SSL
dig +short n8n.yourdomain.com
curl -I https://n8n.yourdomain.com

# 4. View recent logs
tail -f /home/jarvis/jarvis-stack/logs/setup_*.log
```

**Still broken?** Continue reading for systematic troubleshooting.

---

## 🔍 Three-Tier Diagnostic System

JarvisJR Stack includes a comprehensive diagnostic system that collects troubleshooting information while maintaining security. **All sensitive data (passwords, keys, tokens) is automatically filtered**.

### ⚡ Basic Diagnostics (< 1 second)
```bash
./jstack.sh --diagnose basic
```
**When to use**: Quick health check, first-time diagnosis
**Includes**: System overview, service status, basic configuration validation

### 🔧 Detailed Diagnostics (< 2 seconds, default)
```bash
./jstack.sh --diagnose
# or
./jstack.sh --diagnose detailed
```
**When to use**: Standard troubleshooting, most common issues
**Includes**: Everything from basic + process analysis, Docker health, log analysis

### 🔬 Comprehensive Diagnostics (~6 seconds)
```bash
./jstack.sh --diagnose comprehensive
```
**When to use**: Complex issues, preparing for support requests
**Includes**: Everything from detailed + network tests, SSL validation, dependency checks

### 📤 Safe Sharing
All diagnostic output is **automatically security-filtered** and safe to share with support teams. Sensitive information is replaced with `[REDACTED]`.

---

## 🎯 Common Issues & Solutions

### 🐳 Docker Problems

#### Issue: "Docker daemon not running"
```bash
# Symptoms
docker ps
# Error: Cannot connect to the Docker daemon

# Quick Fix
sudo systemctl start docker
sudo systemctl enable docker

# If still broken
./jstack.sh --diagnose basic
```

#### Issue: Permission denied accessing Docker
```bash
# Symptoms  
docker ps
# Error: permission denied while trying to connect

# Solution
sudo usermod -aG docker $USER
newgrp docker
# Then logout and login again
```

#### Issue: Container won't start
```bash
# Diagnosis
docker ps -a
docker logs [container-name]

# Common solutions
docker restart [container-name]
# or
./jstack.sh --diagnose detailed
```

### 🌐 DNS & Network Issues

#### Issue: "Domain not resolving"
```bash
# Test DNS resolution
dig +short n8n.yourdomain.com
dig +short studio.yourdomain.com  
dig +short supabase.yourdomain.com

# Should return your server IP
# If not, check DNS provider settings
```

#### Issue: "SSL certificate errors"
```bash
# Check certificate status
./jstack.sh --diagnose comprehensive

# Renew certificates manually
./jstack.sh --configure-ssl

# Check certificate expiry
echo | openssl s_client -servername n8n.yourdomain.com -connect yourdomain.com:443 2>/dev/null | openssl x509 -noout -dates
```

#### Issue: "Services not accessible externally"
```bash
# Check firewall
sudo ufw status

# Should show:
# 80/tcp ALLOW IN
# 443/tcp ALLOW IN
# 22/tcp ALLOW IN

# If not configured:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### ⚙️ Configuration Problems

#### Issue: "Configuration file missing"
```bash
# Error: jstack.config not found

# Solution
cp jstack.config.default jstack.config
nano jstack.config
# Set DOMAIN and EMAIL (required)
```

#### Issue: "Domain or email not set"
```bash
# Check configuration
./jstack.sh --diagnose basic

# Fix configuration
nano jstack.config
# Ensure these are set:
# DOMAIN=yourdomain.com
# EMAIL=you@yourdomain.com
```

#### Issue: "Service user doesn't exist"
```bash
# Check if jarvis user exists
id jarvis

# Create if missing
sudo useradd -m -s /bin/bash jarvis
sudo usermod -aG sudo jarvis
sudo usermod -aG docker jarvis
```

### 💾 Database Issues

#### Issue: "PostgreSQL not responding"
```bash
# Check database health
docker exec supabase-db pg_isready

# If failed, check logs
docker logs supabase-db

# Restart database
docker restart supabase-db
```

#### Issue: "Database connection refused"
```bash
# Check if database container is running
docker ps | grep supabase-db

# Check network connectivity
docker exec -it n8n ping supabase-db

# Full diagnostic
./jstack.sh --diagnose detailed
```

### 🧠 N8N Workflow Issues

#### Issue: "N8N not accessible"
```bash
# Test N8N health endpoint
curl -s http://localhost:5678/healthz

# Check N8N logs
docker logs n8n

# Check reverse proxy
docker logs nginx-proxy
```

#### Issue: "Workflows not saving"
```bash
# Check database connection from N8N
docker exec -it n8n node -e "console.log('DB connection test')"

# Check disk space
df -h

# Check N8N configuration
./jstack.sh --diagnose comprehensive
```

---

## 🔥 Emergency Recovery Procedures

### 🚑 Complete System Recovery

If everything is broken:

```bash
# 1. Stop all services
docker stop $(docker ps -aq)

# 2. Check system resources
df -h
free -h

# 3. Restart Docker daemon
sudo systemctl restart docker

# 4. Restart all containers
docker start $(docker ps -aq)

# 5. Full diagnostic
./jstack.sh --diagnose comprehensive
```

### 💾 Restore from Backup

```bash
# List available backups
./jstack.sh --list-backups

# Restore latest backup
./jstack.sh --restore

# Or restore specific backup
./jstack.sh --restore backup_20250109_203045.tar.gz
```

### 🔄 Clean Reinstall

**⚠️ Warning: This will remove all data**

```bash
# Complete uninstall
./jstack.sh --uninstall

# Clean Docker
docker system prune -a --volumes

# Reinstall
git pull  # Get latest updates
./jstack.sh --install
```

---

## 📊 Performance Troubleshooting

### 🐌 Slow Performance

#### Check System Resources
```bash
# CPU and memory usage
top
htop

# Disk usage and I/O
df -h
iostat -x 1

# Container resource usage
docker stats
```

#### Optimize Container Resources
```bash
# Check container limits
docker inspect [container-name] | grep -A 10 "Memory"

# View current resource usage
docker exec [container-name] cat /proc/meminfo
```

### 🔥 High Resource Usage

#### Identify Resource-Heavy Containers
```bash
# Sort by CPU usage
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" --no-stream

# Check logs for errors causing resource spikes
docker logs --tail 100 [container-name] | grep -i error
```

#### Quick Resource Fixes
```bash
# Restart resource-heavy container
docker restart [container-name]

# Clear container logs
docker exec [container-name] truncate -s 0 /proc/1/fd/1
docker exec [container-name] truncate -s 0 /proc/1/fd/2

# Clean up Docker system
docker system prune
```

---

## 🔍 Advanced Debugging

### 🔬 Deep Diagnosis Commands

```bash
# Container inspection
docker inspect [container-name]

# Network diagnosis
docker network ls
docker network inspect [network-name]

# Volume diagnosis  
docker volume ls
docker volume inspect [volume-name]

# Service-specific health checks
docker exec supabase-db pg_isready -h localhost -p 5432
docker exec nginx-proxy nginx -t
curl -f http://localhost:5678/healthz
```

### 📝 Log Analysis

#### Access Service Logs
```bash
# JarvisJR Stack logs
tail -f /home/jarvis/jarvis-stack/logs/setup_*.log

# Container logs
docker logs -f [container-name]

# System logs
sudo journalctl -u docker -f
sudo tail -f /var/log/syslog | grep docker
```

#### Search for Specific Issues
```bash
# Search for errors in logs
grep -i "error\|fail\|exception" /home/jarvis/jarvis-stack/logs/setup_*.log

# Search container logs
docker logs [container-name] 2>&1 | grep -i error

# Search all logs with timestamp
find /home/jarvis/jarvis-stack/logs -name "*.log" -exec grep -l "error" {} \;
```

---

## 🛡️ Security Troubleshooting

### 🔒 SSL Certificate Issues

#### Check Certificate Status
```bash
# Test SSL certificate validity
echo | openssl s_client -servername n8n.yourdomain.com -connect n8n.yourdomain.com:443 2>/dev/null | openssl x509 -noout -text

# Check Let's Encrypt status
sudo certbot certificates

# Check certificate files
ls -la /etc/letsencrypt/live/yourdomain.com/
```

#### Renew Certificates
```bash
# Manual renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# JarvisJR Stack SSL management
./jstack.sh --configure-ssl
```

### 🔥 Firewall Issues

#### Check Firewall Status
```bash
# UFW status
sudo ufw status verbose

# Check if ports are listening
netstat -tuln | grep -E ':80|:443|:22'

# Test port connectivity
telnet yourdomain.com 80
telnet yourdomain.com 443
```

#### Fix Firewall Configuration
```bash
# Reset firewall rules
sudo ufw --force reset

# Apply correct rules
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp  
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## 📞 Getting Support

### 📝 Preparing Support Request

**Before requesting support, gather this information:**

1. **Run comprehensive diagnostics**:
   ```bash
   ./jstack.sh --diagnose comprehensive > diagnostic_report.txt
   ```

2. **Include system information**:
   ```bash
   echo "OS: $(lsb_release -d | cut -f2-)" >> diagnostic_report.txt
   echo "Docker: $(docker --version)" >> diagnostic_report.txt
   echo "Domain: $DOMAIN" >> diagnostic_report.txt
   ```

3. **Describe the problem**:
   - What were you trying to do?
   - What happened instead?
   - When did it start occurring?
   - Any recent changes to the system?

### 🔗 Support Channels

- **🐛 Bug Reports**: [GitHub Issues](https://github.com/odysseyalive/jstack/issues)
- **💬 Community**: [AI Productivity Hub](https://www.skool.com/ai-productivity-hub)
- **📧 Enterprise**: enterprise@jstack.com

### 📋 Support Request Template

```markdown
## Problem Description
[Describe what's happening and what you expected]

## Environment Information
- OS: [Your operating system]
- Domain: [Your domain name]
- Installation Date: [When you installed JarvisJR Stack]

## Steps to Reproduce
1. [First step]
2. [Second step]
3. [Result]

## Diagnostic Information
[Paste output of `./jstack.sh --diagnose comprehensive`]

## Additional Context
[Any other relevant information]
```

---

## ✅ Prevention & Maintenance

### 🔄 Regular Health Checks

**Weekly maintenance routine:**

```bash
# 1. System health check
./jstack.sh --diagnose basic

# 2. Update system packages
sudo apt update && sudo apt upgrade

# 3. Clean Docker system
docker system prune

# 4. Check disk space
df -h

# 5. Backup system
./jstack.sh --backup weekly-maintenance
```

### 📊 Monitoring Setup

**Set up automated monitoring:**

```bash
# Create monitoring script
cat > ~/jarvis-health-check.sh << 'EOF'
#!/bin/bash
# Weekly health check
./jstack.sh --diagnose basic
if [ $? -ne 0 ]; then
    echo "Health check failed - investigate immediately"
    ./jstack.sh --diagnose comprehensive > /tmp/health-failure-$(date +%Y%m%d).log
fi
EOF

chmod +x ~/jarvis-health-check.sh

# Add to cron for weekly execution
(crontab -l 2>/dev/null; echo "0 9 * * 1 $HOME/jarvis-health-check.sh") | crontab -
```

### 🎯 Best Practices

- **Regular Backups**: Use `./jstack.sh --backup` before major changes
- **Monitor Resources**: Check `docker stats` regularly
- **Keep Updated**: Run `./jstack.sh --sync` for updates
- **DNS Monitoring**: Verify domain resolution weekly
- **Certificate Monitoring**: Check SSL certificates monthly
- **Log Review**: Check logs for warnings and errors weekly

---

## 🎓 Understanding JarvisJR Stack

### 🏗️ Architecture Overview

```
Internet → NGINX Proxy → Docker Networks → Services
          (SSL/Security)                    ├─ Supabase (API + DB)
                                           ├─ N8N Workflows  
                                           └─ Chrome Browser
```

### 🔍 Key Components

- **NGINX**: Reverse proxy handling SSL and routing
- **Supabase**: PostgreSQL database with API layer
- **N8N**: Workflow automation engine
- **Chrome**: Browser automation for workflows
- **Docker**: Containerization platform

### 📂 Important Directories

```
/home/jarvis/jarvis-stack/
├── logs/          # All system logs
├── backups/       # System backups
├── config/        # Service configurations
└── data/          # Persistent data
```

---

**💡 Remember**: When in doubt, run `./jstack.sh --diagnose` first. It's designed to identify and help resolve 90% of common issues automatically.

---

*For more guides, see: [Installation](installation.md) | [Configuration](configuration.md) | [Service Management](service-management.md)*