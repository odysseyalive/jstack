# Backup & Recovery Guide

Your data is valuable. JStack makes backing up and restoring your entire infrastructure simple and reliable.

## The nightly full backup (as of 2026-10-10)

The jstack user's crontab runs `scripts/core/backup_restore.sh backup --full` at 03:00,
writing to `backups/cron.log`. It runs as that user, never root. Root-owned files are
read through a throwaway container. One archive, `backups/jstack_full_<ts>.tar.gz`
(mode 600 in a 700 directory), holds:

- `docker-compose.yml`, `jstack.config`, `nginx/conf.d/`, and `sites/` without
  `node_modules`, `.next`, `.next-prev`, `trivy-cache`, live Postgres data
  directories and scratch `tmp/` dirs
- `sites/<site>/db-dumps/<db>.pgdump`: `pg_dump -Fc` of each Convex site's Postgres,
  which includes the function env store (JWT keys, ADMIN_USER, SMTP_*)
- `sites/<site>/db-dumps/convex-export.zip`: `convex export --include-file-storage`.
  It does NOT carry the env store, so the pgdump is needed too.
- `nginx/certbot-conf.tar`: the whole certbot tree, root-owned, private keys 0600

The run validates its own archive: gzip, member roots, each pgdump through
`pg_restore -l`, each export through the site's `convex_zip_check`, and the certbot tar
listing. A failed check fails the run.

**Restore** (rehearse into a scratch copy, never the live tree):

```bash
mkdir -p /tmp/drill/scripts/core
cp scripts/core/backup_restore.sh scripts/core/jstack_config.sh /tmp/drill/scripts/core/
cp jstack.config /tmp/drill/
bash /tmp/drill/scripts/core/backup_restore.sh restore backups/jstack_full_<ts>.tar.gz
```

The restore unpacks the certbot tar through a container, so the keys come back
root-owned. It does not load databases; that's a per-site decision. To load a dump
into a stopped site's fresh Postgres:

```bash
docker exec -i <site>-convex-postgres-1 pg_restore -U convex -d <db> --clean --if-exists \
  < sites/<site>/db-dumps/<db>.pgdump
```

Drill of 2026-10-10: both pgdumps loaded into a throwaway `postgres` container with
no errors, and the certbot tree came back root-owned with keys at 0600. Importing an
export zip into a fresh Convex backend has not been rehearsed yet.

The sections below predate this script and describe `jstack.sh --backup`.

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
ls -la sites/
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