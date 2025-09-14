# SSL & Security Guide

JStack secures your infrastructure by default. Here's how SSL certificates, firewalls, and security work—and how to manage them.

## SSL Certificates - Your Security Foundation

### Understanding SSL in JStack

**Automatic SSL:** JStack uses Certbot to get free SSL certificates from Let's Encrypt
**Self-signed fallback:** Generates temporary certificates for immediate testing
**Auto-renewal:** Certificates renew automatically before expiration

### Certificate Locations
- Real SSL certificates (Let's Encrypt)
```bash
ls -la nginx/ssl/live/yourdomain.com/
```
- Self-signed certificates (for testing)
```bash
ls -la nginx/ssl/selfsigned/
```

### Managing SSL Certificates
- List all certificates
```bash
ls -la nginx/ssl/live/*/
```
- Check expiration date
```bash
openssl x509 -in nginx/ssl/live/yourdomain.com/cert.pem -text -noout | grep "Not After"
```
- Test certificate validity
```bash
openssl x509 -in nginx/ssl/live/yourdomain.com/cert.pem -text -noout
```
- Create self-signed for testing
```bash
bash scripts/core/ssl_cert.sh generate_self_signed yourdomain.com admin@yourdomain.com
```
- Get Let's Encrypt certificate
```bash
bash scripts/core/setup_ssl_certbot.sh yourdomain.com
```
- Setup SSL for all service subdomains
```bash
bash scripts/core/setup_service_subdomains_ssl.sh
```
- Renew specific domain
```bash
certbot renew --cert-name yourdomain.com
```
- Renew all certificates
```bash
certbot renew
```
- Restart NGINX after renewal
```bash
docker-compose restart nginx
```

## NGINX Security Configuration

### Security Headers
Edit files in `nginx/conf.d/*.conf` to add headers:
```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### Rate Limiting
Edit `nginx/nginx.conf` to adjust limits:
```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=web:10m rate=30r/s;
```

### SSL Configuration
Add these to your NGINX SSL config:
```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

## Fail2ban Protection
- See banned IPs
```bash
sudo fail2ban-client status sshd
```
```bash
sudo fail2ban-client status nginx-http-auth
```
- Unban specific IP
```bash
sudo fail2ban-client set sshd unbanip 192.168.1.100
```
- Configure ban rules (edit /etc/fail2ban/jail.local)
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
- Restart Fail2ban after changes
```bash
sudo systemctl restart fail2ban
```
```bash
sudo systemctl status fail2ban
```

## Firewall Configuration
- Check current rules
```bash
sudo ufw status
```
- Default JStack rules
```bash
sudo ufw allow 22/tcp
```
```bash
sudo ufw allow 80/tcp
```
```bash
sudo ufw allow 443/tcp
```
```bash
sudo ufw enable
```
- Allow database access from specific IP
```bash
sudo ufw allow from 192.168.1.100 to any port 5432
```
- Allow custom application port
```bash
sudo ufw allow 8080/tcp
```
- Block specific IP
```bash
sudo ufw deny from 192.168.1.200
```
- List numbered rules
```bash
sudo ufw status numbered
```
- Delete rule by number
```bash
sudo ufw delete 3
```

## Container Security
- See what user containers run as
```bash
docker-compose exec n8n whoami
```
```bash
docker-compose exec supabase-db whoami
```
- View Docker networks
```bash
docker network ls
```
- Inspect JStack network
```bash
docker network inspect jstack_default
```
- Check volume permissions
```bash
ls -la data/
```
```bash
ls -la nginx/
```
- Fix permissions if needed
```bash
./scripts/core/fix_workspace_permissions.sh
```

## Security Best Practices
- Update n8n/Supabase credentials
```bash
export N8N_BASIC_AUTH_USER="your-secure-username"
```
```bash
export N8N_BASIC_AUTH_PASSWORD="your-long-secure-password"
```
```bash
export SUPABASE_USER="your-db-username"
```
```bash
export SUPABASE_PASSWORD="your-long-secure-db-password"
```
- Apply changes
```bash
docker-compose up -d
```
- Update system packages
```bash
sudo apt update && sudo apt upgrade
```
- Update Docker images
```bash
docker-compose pull
```
```bash
docker-compose up -d
```
- Update JStack scripts
```bash
git pull origin main
```
- Encrypt backups
```bash
tar -czf - data/ nginx/ | gpg --cipher-algo AES256 --compress-algo 1 --symmetric --output backup-$(date +%Y%m%d).tar.gz.gpg
```
- Decrypt backups
```bash
gpg --decrypt backup-20240115.tar.gz.gpg | tar -xzf -
```

## Access Control
Edit `/etc/ssh/sshd_config` as needed:
```bash
PermitRootLogin no
```
```bash
PasswordAuthentication no
```
```bash
PubkeyAuthentication yes
```
```bash
AllowUsers yourusername
```
- Restart SSH after changes
```bash
sudo systemctl restart sshd
```

## Security Monitoring
- SSH attempts
```bash
sudo journalctl -u ssh
```
- NGINX access logs
```bash
docker-compose logs nginx | grep -E "(404|403|401)"
```
- Fail2ban logs
```bash
sudo journalctl -u fail2ban
```
- Install logwatch
```bash
sudo apt install logwatch
```
- Configure email alerts
```bash
sudo nano /etc/logwatch/conf/logwatch.conf
```
# Set MailTo = your@email.com
- Test logwatch
```bash
sudo logwatch --detail low --mailto your@email.com --service ssh
```
- Run security validation
```bash
./jstack.sh compliance
```
- Check SSL configuration
```bash
./jstack.sh validate
```
- Test SSL strength
```bash
testssl.sh yourdomain.com
```

## Incident Response
- Check active connections
```bash
sudo netstat -tlnp
```
- Review recent logins
```bash
last -20
```
- Check running processes
```bash
ps aux | grep -v grep
```
- Review fail2ban logs
```bash
sudo fail2ban-client status
```
- Block IP immediately
```bash
sudo ufw deny from 192.168.1.200
```
- Ban IP in fail2ban
```bash
sudo fail2ban-client set sshd banip 192.168.1.200
```
- Change system password
```bash
passwd
```
- Reset n8n/database credentials and apply changes
```bash
export N8N_BASIC_AUTH_USER="newuser"
```
```bash
export N8N_BASIC_AUTH_PASSWORD="newpassword"
```
```bash
export SUPABASE_PASSWORD="newdbpassword"
```
```bash
docker-compose up -d
```

## Certificate Automation
- Check if auto-renewal is active
```bash
sudo systemctl status certbot.timer
```
- Enable auto-renewal
```bash
sudo systemctl enable certbot.timer
```
```bash
sudo systemctl start certbot.timer
```
- Test renewal process
```bash
sudo certbot renew --dry-run
```
- Custom renewal hook example (/etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh):
```bash
#!/bin/bash
docker-compose -f /path/to/jstack/docker-compose.yml restart nginx
```
- Make renewal hook executable
```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
```

Regular monitoring and updates keep your stack secure as threats evolve.