# Backup & Recovery Guide

Your data is valuable. JStack makes backing up and restoring your entire infrastructure simple and reliable.

## Understanding JStack Backups

### What Gets Backed Up

**Critical data included:**
- Database files (`data/supabase/`)
- n8n workflows and data (`data/n8n/`)
- NGINX configurations (`nginx/conf.d/`)
- SSL certificates (`nginx/ssl/`)
- Site configurations and content (`sites/`)
- Application logs (`logs/`)
- Docker configuration files

**What's NOT included:**
- Docker images (downloaded fresh during restore)
- System packages (installed during restore)
- Temporary files and cache

### Backup Storage Location

```bash
# Default backup directory
./backups/
├── backup-2024-01-15-14-30-00.tar.gz
├── backup-2024-01-14-14-30-00.tar.gz
└── backup-2024-01-13-14-30-00.tar.gz
```

## Creating Backups

### Manual Backup

**Create backup immediately:**
```bash
# Full system backup
./jstack.sh --backup

# Backup with custom name
./jstack.sh --backup my-pre-update-backup
```

**Check backup contents:**
```bash
# List backup files
ls -la backups/

# View backup contents without extracting
tar -tzf backups/backup-2024-01-15-14-30-00.tar.gz
```

### Automated Backups

**Setup daily backups:**
```bash
# Add to crontab
crontab -e

# Add this line for daily backup at 2 AM
0 2 * * * cd /path/to/jstack && ./jstack.sh --backup >> logs/backup.log 2>&1
```

**Setup weekly backups:**
```bash
# Weekly backup on Sundays at 3 AM
0 3 * * 0 cd /path/to/jstack && ./jstack.sh --backup weekly-$(date +\%Y\%m\%d) >> logs/backup.log 2>&1
```

### Backup Before Major Changes

**Pre-update backup:**
```bash
# Before updating JStack
./jstack.sh --backup pre-update-$(date +%Y%m%d)

# Before major configuration changes
./jstack.sh --backup pre-ssl-setup

# Before adding new sites
./jstack.sh --backup pre-new-site
```

## Restoring from Backups

### Complete System Restore

**Restore everything:**
```bash
# Stop all services first
./jstack.sh down

# Restore from backup
./jstack.sh --restore backups/backup-2024-01-15-14-30-00.tar.gz

# Start services
./jstack.sh up
```

### Selective Restore

**Restore specific components:**
```bash
# Extract backup to temporary location
mkdir temp-restore
tar -xzf backups/backup-2024-01-15-14-30-00.tar.gz -C temp-restore

# Restore only database
./jstack.sh down
rm -rf data/supabase/
cp -r temp-restore/data/supabase/ data/
./jstack.sh up

# Restore only NGINX configs
cp -r temp-restore/nginx/conf.d/* nginx/conf.d/
docker-compose restart nginx
```

### Point-in-Time Recovery

**Restore to specific backup:**
```bash
# List available backups
ls -la backups/

# Choose backup from specific date
./jstack.sh --restore backups/backup-2024-01-10-14-30-00.tar.gz
```

## Advanced Backup Strategies

### Remote Backups

**Backup to remote server:**
```bash
# Create backup and upload
./jstack.sh --backup
scp backups/backup-$(date +%Y%m%d)*.tar.gz user@remote-server:/backups/jstack/

# Automated remote backup
echo "0 3 * * * cd /path/to/jstack && ./jstack.sh --backup && scp backups/backup-\$(date +\%Y\%m\%d)*.tar.gz user@remote:/backups/" | crontab -
```

**Backup to cloud storage:**
```bash
# Install AWS CLI or similar
sudo apt install awscli

# Upload to S3 after backup
./jstack.sh --backup
aws s3 cp backups/backup-$(date +%Y%m%d)*.tar.gz s3://your-backup-bucket/jstack/
```

### Encrypted Backups

**Create encrypted backup:**
```bash
# Backup and encrypt
./jstack.sh --backup
gpg --cipher-algo AES256 --compress-algo 1 --symmetric --output backups/backup-$(date +%Y%m%d)-encrypted.tar.gz.gpg backups/backup-$(date +%Y%m%d)*.tar.gz
```

**Restore encrypted backup:**
```bash
# Decrypt and restore
gpg --decrypt backups/backup-20240115-encrypted.tar.gz.gpg > temp-backup.tar.gz
./jstack.sh --restore temp-backup.tar.gz
rm temp-backup.tar.gz
```

### Incremental Backups

**Database-only backups (faster):**
```bash
# Backup just database data
tar -czf backups/db-backup-$(date +%Y%m%d).tar.gz data/supabase/

# Backup just n8n workflows
tar -czf backups/n8n-backup-$(date +%Y%m%d).tar.gz data/n8n/
```

## Backup Validation

### Test Backup Integrity

**Verify backup file:**
```bash
# Check if backup file is valid
tar -tzf backups/backup-2024-01-15-14-30-00.tar.gz > /dev/null
echo $? # Should return 0 if valid
```

**Test restore process:**
```bash
# Create test environment
mkdir test-restore
cd test-restore

# Extract backup
tar -xzf ../backups/backup-2024-01-15-14-30-00.tar.gz

# Verify critical files exist
ls -la data/supabase/
ls -la data/n8n/
ls -la nginx/conf.d/
```

### Automated Backup Testing

**Weekly backup verification:**
```bash
#!/bin/bash
# save as scripts/test-backup.sh

LATEST_BACKUP=$(ls -t backups/*.tar.gz | head -1)
echo "Testing backup: $LATEST_BACKUP"

# Create test directory
mkdir -p /tmp/backup-test
cd /tmp/backup-test

# Extract and verify
if tar -xzf "$LATEST_BACKUP"; then
    echo "✓ Backup extraction successful"
    
    # Check critical directories
    if [ -d "data/supabase" ] && [ -d "data/n8n" ] && [ -d "nginx" ]; then
        echo "✓ Critical directories present"
        echo "✓ Backup validation passed"
    else
        echo "✗ Missing critical directories"
        exit 1
    fi
else
    echo "✗ Backup extraction failed"
    exit 1
fi

# Cleanup
cd /
rm -rf /tmp/backup-test
```

## Disaster Recovery Procedures

### Complete System Loss

**Recovery steps:**
1. **Fresh server setup:**
```bash
# On new server
git clone https://github.com/odysseyalive/jstack.git
cd jstack
sudo -v
```

2. **Restore from backup:**
```bash
# Copy backup to new server
scp user@backup-server:/backups/latest-backup.tar.gz backups/

# Restore everything
./jstack.sh --restore backups/latest-backup.tar.gz
```

3. **Verify services:**
```bash
# Check all services
./jstack.sh status
./jstack.sh diagnostics

# Test web access
curl -I https://yourdomain.com
```

### Partial Recovery Scenarios

**Database corruption:**
```bash
# Stop services
./jstack.sh down

# Restore only database
tar -xzf backups/latest-backup.tar.gz data/supabase/
./jstack.sh up

# Verify database
docker-compose exec supabase-db pg_isready
```

**Lost SSL certificates:**
```bash
# Restore certificates
tar -xzf backups/latest-backup.tar.gz nginx/ssl/

# Or regenerate
bash scripts/core/setup_ssl_certbot.sh yourdomain.com
docker-compose restart nginx
```

**Lost NGINX configuration:**
```bash
# Restore NGINX configs
tar -xzf backups/latest-backup.tar.gz nginx/conf.d/
docker-compose restart nginx
```

## Backup Management

### Cleanup Old Backups

**Manual cleanup:**
```bash
# Keep only last 7 days
find backups/ -name "backup-*.tar.gz" -mtime +7 -delete

# Keep only last 10 backups
ls -t backups/backup-*.tar.gz | tail -n +11 | xargs rm -f
```

**Automated cleanup:**
```bash
# Add to backup script
#!/bin/bash
# Create backup
./jstack.sh --backup

# Keep only last 14 backups
ls -t backups/backup-*.tar.gz | tail -n +15 | xargs rm -f

# Log cleanup
echo "$(date): Backup created, old backups cleaned" >> logs/backup.log
```

### Backup Monitoring

**Check backup status:**
```bash
# Last backup time
ls -la backups/ | head -2

# Backup sizes (watch for unusual sizes)
du -h backups/

# Backup frequency check
find backups/ -name "backup-*.tar.gz" -mtime -1 | wc -l
```

**Alert on backup failures:**
```bash
# In backup script
if ./jstack.sh --backup; then
    echo "$(date): Backup successful" >> logs/backup.log
else
    echo "$(date): Backup FAILED" >> logs/backup.log
    # Send alert email
    echo "JStack backup failed on $(hostname)" | mail -s "Backup Alert" admin@yourdomain.com
fi
```

## Best Practices

### Backup Schedule

**Recommended frequency:**
- **Production systems:** Daily backups, keep 30 days
- **Development systems:** Weekly backups, keep 4 weeks
- **Before major changes:** Always create backup first

### Storage Strategy

**3-2-1 Rule:**
- **3** copies of important data
- **2** different storage media
- **1** offsite backup

**Implementation:**
```bash
# Local backup
./jstack.sh --backup

# Copy to network storage
cp backups/latest*.tar.gz /mnt/nas/jstack-backups/

# Upload to cloud
aws s3 sync backups/ s3://your-backup-bucket/jstack/
```

### Security

**Protect backup files:**
```bash
# Restrict backup directory permissions
chmod 700 backups/
chmod 600 backups/*.tar.gz

# Encrypt sensitive backups
gpg --symmetric backups/backup-$(date +%Y%m%d).tar.gz
```

Your data is now protected with reliable backup and recovery procedures. Regular backups mean you can focus on building without worrying about data loss.