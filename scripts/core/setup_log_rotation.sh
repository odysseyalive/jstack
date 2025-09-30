#!/bin/bash
# JStack Log Rotation Setup Script
# Configures logrotate for application and NGINX logs

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

JSTACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGROTATE_CONF="/etc/logrotate.d/jstack"

log "Setting up log rotation for JStack..."

# Check if logrotate is installed
if ! command -v logrotate &>/dev/null; then
  log "logrotate not found. Installing..."
  sudo apt-get update
  sudo apt-get install -y logrotate
fi

# Create logrotate configuration
log "Creating logrotate configuration at $LOGROTATE_CONF..."

sudo tee "$LOGROTATE_CONF" > /dev/null <<EOF
# JStack Application Logs
$JSTACK_DIR/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 $USER $USER
    dateext
    dateformat -%Y%m%d
    maxsize 10M
}

# NGINX Logs (managed via Docker volume)
$JSTACK_DIR/nginx/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0644 root root
    dateext
    dateformat -%Y%m%d
    maxsize 50M
    sharedscripts
    postrotate
        # Reopen NGINX log files
        if docker ps -q -f name=nginx 2>/dev/null | grep -q .; then
            docker exec nginx nginx -s reopen >/dev/null 2>&1 || true
        fi
    endscript
}

# n8n Logs (if needed - n8n has its own rotation)
$JSTACK_DIR/data/n8n/*.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 0644 1000 1000
    dateext
    dateformat -%Y%m%d
    maxsize 25M
}
EOF

# Ensure logs directory exists
mkdir -p "$JSTACK_DIR/logs"

# Set proper permissions on logrotate config
sudo chmod 0644 "$LOGROTATE_CONF"

# Test the configuration
log "Testing logrotate configuration..."
TEST_OUTPUT=$(sudo logrotate -d "$LOGROTATE_CONF" 2>&1)
if echo "$TEST_OUTPUT" | grep -i "^error:"; then
  log "ERROR: logrotate configuration test failed!"
  echo "$TEST_OUTPUT"
  exit 1
fi

log "✓ Log rotation configured successfully"
log "Configuration details:"
log "  - Application logs (logs/*.log): Daily rotation, 7 days retention, max 10MB"
log "    Files: backup_restore.log, site_template_lifecycle.log (created on-demand)"
log "  - NGINX logs (nginx/logs/*.log): Daily rotation, 14 days retention, max 50MB"
log "    Files: access.log, error.log"
log "  - n8n logs (data/n8n/*.log): Weekly rotation, 4 weeks retention, max 25MB"
log "    Files: n8nEventLog*.log (n8n manages its own rotation)"
log ""
log "Note: Log files are created on-demand. Missing files are handled gracefully."
log ""
log "To manually test log rotation, run:"
log "  sudo logrotate -f $LOGROTATE_CONF"
log ""
log "Logs will be automatically rotated by the system logrotate cron job (daily)."
