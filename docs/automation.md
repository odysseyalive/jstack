# Automation & Monitoring Guide

jstack automates SSL certificate renewal, backups, cleanup, health checks,
and maintenance using cron jobs and scripts. Here's how these routines work
and how to customize or monitor them.

## Setting Up Built-in Automation

- Setup all automation (SSL renewal + backups)
```bash
bash scripts/core/setup_cron_jobs.sh install
```
- Check status
```bash
bash scripts/core/setup_cron_jobs.sh status
```
- Remove automation
```bash
bash scripts/core/setup_cron_jobs.sh remove
```

## Custom Cron Jobs Examples (crontab -e)

- Hourly backup during business hours
```bash
0 9-17 * * 1-5 cd /path/to/jstack && ./jstack.sh --backup hourly-$(date +\%H)
```
- Health check every 15 minutes
```bash
*/15 * * * * cd /path/to/jstack && ./jstack.sh status | grep running || echo "Service down on $(hostname)" | mail -s "JStack Alert" admin@yourdomain.com
```
- Daily disk space safe guard
```bash
0 6 * * * df -h | awk '$5 > 80 {print $0}' | mail -s "Disk Space Warning" admin@yourdomain.com
```

Site-specific backups (database dumps, file snapshots) belong in the site's
own cron — each `sites/<domain>/` knows what it needs to back up.

## Monitoring & Logging

- View cron execution logs
```bash
sudo journalctl -u cron
```
- Check system mail for cron output
```bash
mail
```
- View recent cron activity
```bash
grep CRON /var/log/syslog | tail -20
```

## Troubleshooting Automation

- Check cron status
```bash
sudo systemctl status cron
```
- Use full paths to binaries in jobs
- Manually test scripts before scheduling

## Tips

- Automate backups, SSL renewals, health checks
- Use mail alerts for service or disk failures
- Schedule remote/cloud backups as needed
