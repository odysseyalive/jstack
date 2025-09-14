# Automation & Monitoring Guide

JStack automates SSL certificate renewal, backups, cleanup, health checks, and maintenance using cron jobs and scripts. Here’s how these routines work and how you can customize or monitor them.

## Automatic Cron Jobs

JStack sets up these jobs with:
```bash
bash scripts/core/setup_cron_jobs.sh install
```

**Defaults:**
- SSL renewal + nginx reload: daily at 2:00 AM
- Full backup: daily at 3:00 AM
- Cleanup old backups: weekly at 4:00 AM Sunday

Check status anytime:
```bash
bash scripts/core/setup_cron_jobs.sh status
```

## Custom Automation

**Examples for crontab (`crontab -e`)**
- Hourly backup during business hours:
  ```bash
  0 9-17 * * 1-5 cd /path/to/jstack && ./jstack.sh --backup hourly-$(date +\%H)
  ```
- Database dump every 6h:
  ```bash
  0 */6 * * * cd /path/to/jstack && docker-compose exec -T supabase-db pg_dump -U postgres postgres | gzip > backups/db-$(date +\%Y\%m\%d-\%H).sql.gz
  ```
- Health check + disk safe guard:
  ```bash
  */15 * * * * cd /path/to/jstack && ./jstack.sh status | grep running || echo "Service down on $(hostname)" | mail -s "JStack Alert" admin@yourdomain.com
  0 6 * * * df -h | awk '$5 > 80 {print $0}' | mail -s "Disk Space Warning" admin@yourdomain.com
  ```

## Monitoring & Logging

- Check cron logs:
  ```bash
  sudo journalctl -u cron
  grep CRON /var/log/syslog | tail -20
  ```
- All JStack routine logs are in `logs/`.
- Add additional jobs (e.g. remote backup sync) in your crontab or scripts.

## Troubleshooting Automation

If jobs aren’t running:
- Confirm cron status:
  ```bash
  sudo systemctl status cron
  ```
- Use full paths to binaries in jobs (`/usr/bin/docker-compose`)
- Keep jobs environment/non-interactive
- Manually test scripts before scheduling

## Tips
- Automate all backups, SSL renewals, and basic health checks
- Use mail alerts for service or disk failures
- Schedule remote backups and advanced automation as needed

JStack’s automation keeps your system healthy, backed up, and secure—minimal manual intervention required.