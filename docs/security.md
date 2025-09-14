# SSL & Security Guide

JStack secures your infrastructure by default. Here's how SSL certificates, firewalls, and security work—and how to manage them.

## SSL Certificates - Your Security Foundation

### Understanding SSL in JStack

**Automatic SSL:** JStack uses Certbot to get free SSL certificates from Let's Encrypt
**Self-signed fallback:** Generates temporary certificates for immediate testing
**Auto-renewal:** Certificates renew automatically before expiration

### Certificate Locations
```bash
# Real SSL certificates (Let's Encrypt)
nginx/ssl/live/yourdomain.com/
├── cert.pem        # Your certificate
├── chain.pem       # Certificate chain
├── fullchain.pem   # cert + chain (used by NGINX)
└── privkey.pem     # Private key

# Self-signed certificates (for testing)
nginx/ssl/selfsigned/
├── yourdomain.com.crt
└── yourdomain.com.key
```

### Managing SSL Certificates

**Check certificate status:**
```bash
# List all certificates
ls -la nginx/ssl/live/*/

# Check expiration date
openssl x509 -in nginx/ssl/live/yourdomain.com/cert.pem -text -noout | grep "Not After"

# Test certificate validity
openssl x509 -in nginx/ssl/live/yourdomain.com/cert.pem -text -noout
```

**Generate certificates manually:**
```bash
# Create self-signed for testing
bash scripts/core/ssl_cert.sh generate_self_signed yourdomain.com admin@yourdomain.com

# Get Let's Encrypt certificate
bash scripts/core/setup_ssl_certbot.sh yourdomain.com

# Setup SSL for all service subdomains
bash scripts/core/setup_service_subdomains_ssl.sh
```

**Force certificate renewal:**
```bash
# Renew specific domain
certbot renew --cert-name yourdomain.com

# Renew all certificates
certbot renew

# Restart NGINX after renewal
docker-compose restart nginx
```

## NGINX Security Configuration

### Security Headers

JStack automatically adds security headers to all sites:

```nginx
# In nginx/conf.d/*.conf files
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### Rate Limiting

**Default rate limits:**
- 10 requests per second per IP
- Burst of 20 requests
- 429 status code for exceeded limits

**Customize rate limiting:**
Edit `nginx/nginx.conf`:
```nginx
# Adjust rate limiting
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=web:10m rate=30r/s;
```

### SSL Configuration

**Strong SSL settings in NGINX:**
```nginx
# Only modern TLS versions
ssl_protocols TLSv1.2 TLSv1.3;

# Strong cipher suites
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

# SSL optimizations
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

## Fail2ban Protection

### What Fail2ban Does

**SSH protection:** Blocks IPs after failed SSH attempts
**NGINX protection:** Blocks IPs after HTTP 404/403 patterns
**Automatic unban:** IPs are unbanned after configured time

### Managing Fail2ban

**Check ban status:**
```bash
# See banned IPs
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-http-auth

# Unban specific IP
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

**Configure ban rules:**
Edit `/etc/fail2ban/jail.local`:
```ini
[sshd]
enabled = true
maxretry = 3
bantime = 3600
findtime = 600

[nginx-http-auth]
enabled = true
maxretry = 5
bantime = 1800
```

**Restart Fail2ban after changes:**
```bash
sudo systemctl restart fail2ban
sudo systemctl status fail2ban
```

## Firewall Configuration

### Default Firewall Rules

JStack configures UFW (Uncomplicated Firewall):

```bash
# Check current rules
sudo ufw status

# Default JStack rules
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

### Custom Firewall Rules

**Allow specific services:**
```bash
# Allow database access from specific IP
sudo ufw allow from 192.168.1.100 to any port 5432

# Allow custom application port
sudo ufw allow 8080/tcp

# Block specific IP
sudo ufw deny from 192.168.1.200
```

**Remove rules:**
```bash
# List numbered rules
sudo ufw status numbered

# Delete rule by number
sudo ufw delete 3
```

## Container Security

### Rootless Containers

**JStack security principles:**
- Services run as non-root users when possible
- Containers have limited system access
- No privileged mode containers

**Check container users:**
```bash
# See what user containers run as
docker-compose exec n8n whoami
docker-compose exec supabase-db whoami
```

### Network Isolation

**Container networks:**
```bash
# View Docker networks
docker network ls

# Inspect JStack network
docker network inspect jstack_default
```

**Network security:**
- Containers can only communicate on defined networks
- External access only through NGINX reverse proxy
- Database not directly accessible from internet

### Volume Security

**Data protection:**
```bash
# Check volume permissions
ls -la data/
ls -la nginx/

# Fix permissions if needed
./scripts/core/fix_workspace_permissions.sh
```

## Security Best Practices

### Strong Passwords

**Change default credentials:**
```bash
# Update n8n credentials
export N8N_BASIC_AUTH_USER="your-secure-username"
export N8N_BASIC_AUTH_PASSWORD="your-long-secure-password"

# Update Supabase credentials  
export SUPABASE_USER="your-db-username"
export SUPABASE_PASSWORD="your-long-secure-db-password"

# Apply changes
docker-compose up -d
```

### Regular Updates

**Keep system updated:**
```bash
# Update system packages
sudo apt update && sudo apt upgrade

# Update Docker images
docker-compose pull
docker-compose up -d

# Update JStack scripts
git pull origin main
```

### Backup Security

**Secure your backups:**
```bash
# Encrypt backups
tar -czf - data/ nginx/ | gpg --cipher-algo AES256 --compress-algo 1 --symmetric --output backup-$(date +%Y%m%d).tar.gz.gpg

# Decrypt backups
gpg --decrypt backup-20240115.tar.gz.gpg | tar -xzf -
```

### Access Control

**Limit SSH access:**
Edit `/etc/ssh/sshd_config`:
```bash
# Disable root login
PermitRootLogin no

# Use key-based authentication
PasswordAuthentication no
PubkeyAuthentication yes

# Limit users
AllowUsers yourusername
```

**Restart SSH after changes:**
```bash
sudo systemctl restart sshd
```

## Security Monitoring

### Log Monitoring

**Check security logs:**
```bash
# SSH attempts
sudo journalctl -u ssh

# NGINX access logs
docker-compose logs nginx | grep -E "(404|403|401)"

# Fail2ban logs
sudo journalctl -u fail2ban
```

### Automated Alerts

**Setup log monitoring:**
```bash
# Install logwatch
sudo apt install logwatch

# Configure email alerts
sudo nano /etc/logwatch/conf/logwatch.conf
# Set MailTo = your@email.com

# Test logwatch
sudo logwatch --detail low --mailto your@email.com --service ssh
```

### Security Compliance Checks

**Run security validation:**
```bash
# JStack compliance check
./jstack.sh compliance

# Check SSL configuration
./jstack.sh validate

# Test SSL strength
testssl.sh yourdomain.com
```

## Incident Response

### Suspected Breach

**Immediate steps:**
```bash
# Check active connections
sudo netstat -tlnp

# Review recent logins
last -20

# Check running processes
ps aux | grep -v grep

# Review fail2ban logs
sudo fail2ban-client status
```

**Block suspicious activity:**
```bash
# Block IP immediately
sudo ufw deny from 192.168.1.200

# Ban IP in fail2ban
sudo fail2ban-client set sshd banip 192.168.1.200
```

### Recovery Steps

**If compromised:**
1. **Isolate:** Block suspicious IPs
2. **Backup:** Save current state for analysis
3. **Reset:** Change all passwords immediately
4. **Update:** Apply all security updates
5. **Monitor:** Watch logs closely for 48 hours

**Password reset process:**
```bash
# Change system password
passwd

# Reset n8n credentials
export N8N_BASIC_AUTH_USER="newuser"
export N8N_BASIC_AUTH_PASSWORD="newpassword"

# Reset database credentials
export SUPABASE_PASSWORD="newdbpassword"

# Apply changes
docker-compose up -d
```

## Certificate Automation

### Auto-renewal Setup

**Certbot auto-renewal:**
```bash
# Check if auto-renewal is active
sudo systemctl status certbot.timer

# Enable auto-renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Test renewal process
sudo certbot renew --dry-run
```

**Custom renewal hook:**
Create `/etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh`:
```bash
#!/bin/bash
docker-compose -f /path/to/jstack/docker-compose.yml restart nginx
```

Make it executable:
```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
```

Your JStack is now secured with industry-standard practices. Regular monitoring and updates keep it secure as threats evolve.