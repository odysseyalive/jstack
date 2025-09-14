# Backup & Recovery Guide

Your data is valuable. JStack makes backing up and restoring your entire infrastructure simple and reliable.

## Manual Backups
- Run a full backup
```bash
./jstack.sh --backup
```
- Custom name for backup
```bash
./jstack.sh --backup my-pre-update-backup
```
- List backup files
```bash
ls -la backups/
```
- View backup contents
```bash
tar -tzf backups/backup-YYYY-MM-DD-HH-MM-SS.tar.gz
```

## Automated Backups
- Open crontab
```bash
crontab -e
```
- Add daily backup
```bash
0 2 * * * cd /path/to/jstack && ./jstack.sh --backup >> logs/backup.log 2>&1
```
- Add weekly backup
```bash
0 3 * * 0 cd /path/to/jstack && ./jstack.sh --backup weekly-$(date +\%Y\%m\%d) >> logs/backup.log 2>&1
```

## Restore from Backup
- Stop all services
```bash
./jstack.sh down
```
- Restore backup
```bash
./jstack.sh --restore backups/backup-YYYY-MM-DD-HH-MM-SS.tar.gz
```
- Start services
```bash
./jstack.sh up
```

## Remote Backup
- Upload to remote server
```bash
scp backups/backup-$(date +%Y%m%d)*.tar.gz user@remote-server:/backups/jstack/
```
- Upload to S3
```bash
aws s3 cp backups/backup-$(date +%Y%m%d)*.tar.gz s3://your-backup-bucket/jstack/
```

## Encrypted Backups
- Encrypt backup
```bash
gpg --cipher-algo AES256 --compress-algo 1 --symmetric --output backups/backup-$(date +%Y%m%d)-encrypted.tar.gz.gpg backups/backup-$(date +%Y%m%d)*.tar.gz
```
- Decrypt backup
```bash
gpg --decrypt backups/backup-YYYYMMDD-encrypted.tar.gz.gpg > temp-backup.tar.gz
```
- Restore decrypted backup
```bash
./jstack.sh --restore temp-backup.tar.gz
```
- Remove temp after restore
```bash
rm temp-backup.tar.gz
```

## Cleanup Old Backups
- Keep only last 7 days
```bash
find backups/ -name "backup-*.tar.gz" -mtime +7 -delete
```
- Keep only last 10 backups
```bash
ls -t backups/backup-*.tar.gz | tail -n +11 | xargs rm -f
```

## Verification
- Test backup integrity
```bash
tar -tzf backups/backup-YYYY-MM-DD-HH-MM-SS.tar.gz > /dev/null
```
- Test restore process
```bash
mkdir test-restore
```
```bash
cd test-restore
```
```bash
tar -xzf ../backups/backup-YYYY-MM-DD-HH-MM-SS.tar.gz
```
```bash
ls -la data/supabase/
```
```bash
ls -la data/n8n/
```
```bash
ls -la nginx/conf.d/
```

## Disaster Recovery
- Setup new server
```bash
git clone https://github.com/odysseyalive/jstack.git
```
```bash
cd jstack
```
```bash
sudo -v
```
- Restore backup
```bash
scp user@backup-server:/backups/latest-backup.tar.gz backups/
```
```bash
./jstack.sh --restore backups/latest-backup.tar.gz
```
- Verify
```bash
./jstack.sh status
```
```bash
./jstack.sh diagnostics
```
```bash
curl -I https://yourdomain.com
```

## Security
- Restrict backups folder
```bash
chmod 700 backups/
```
- Restrict backup file access
```bash
chmod 600 backups/*.tar.gz
```
- Encrypt sensitive backups
```bash
gpg --symmetric backups/backup-$(date +%Y%m%d).tar.gz
```

Regular backups mean you can focus on building without worrying about data loss.