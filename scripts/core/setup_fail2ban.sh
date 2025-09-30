#!/bin/bash
# JStack Fail2ban Setup Script
# Usage: setup_fail2ban.sh
#
# Configures fail2ban to protect:
# - SSH (port 22) from brute force attacks
# - NGINX (ports 80/443) from malicious traffic patterns

set -e

WORKSPACE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NGINX_LOG_DIR="$WORKSPACE_ROOT/nginx/logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Setting up Fail2ban for SSH and NGINX security..."

# Check if fail2ban is installed
if ! command -v fail2ban-server >/dev/null 2>&1; then
  log "Fail2ban not found. Installing..."
  sudo apt update
  sudo apt install -y fail2ban python3-systemd
  log "✓ Fail2ban installed"
else
  log "✓ Fail2ban already installed"
fi

# Check if python3-systemd is installed (required for systemd backend)
if ! python3 -c "import systemd" 2>/dev/null; then
  log "python3-systemd not found. Installing..."
  sudo apt install -y python3-systemd
  log "✓ python3-systemd installed"
else
  log "✓ python3-systemd already installed"
fi

# Create jail.local if it doesn't exist
if [ ! -f "/etc/fail2ban/jail.local" ]; then
  log "Creating /etc/fail2ban/jail.local..."
  sudo tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
[DEFAULT]
# Ban duration (10 minutes default)
bantime = 10m

# Time window to count failures (10 minutes)
findtime = 10m

# Number of failures before ban
maxretry = 5

# Ignore localhost
ignoreip = 127.0.0.1/8 ::1

# Email notifications (set destemail and enable actions if desired)
# destemail = admin@example.com
# action = %(action_mwl)s

EOF
  log "✓ Created jail.local with default settings"
else
  log "✓ jail.local already exists"
fi

# Configure SSH jail
log "Configuring SSH protection..."
if ! sudo grep -q "^\[sshd\]" /etc/fail2ban/jail.local; then
  sudo tee -a /etc/fail2ban/jail.local > /dev/null <<'EOF'

[sshd]
enabled = true
port = ssh
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h

EOF
  log "✓ SSH jail configured (using systemd backend)"
else
  log "✓ SSH jail already exists"
fi

# Configure NGINX jails for HTTP/HTTPS traffic monitoring
log "Configuring NGINX protection..."

# nginx-http-auth: Ban IPs with repeated HTTP auth failures
if ! sudo grep -q "^\[nginx-http-auth\]" /etc/fail2ban/jail.local; then
  sudo tee -a /etc/fail2ban/jail.local > /dev/null <<EOF

[nginx-http-auth]
enabled = true
port = http,https
logpath = $NGINX_LOG_DIR/error.log
maxretry = 3
findtime = 10m
bantime = 1h

EOF
  log "✓ nginx-http-auth jail configured"
fi

# nginx-limit-req: Ban IPs triggering rate limits (too many requests)
if ! sudo grep -q "^\[nginx-limit-req\]" /etc/fail2ban/jail.local; then
  sudo tee -a /etc/fail2ban/jail.local > /dev/null <<EOF

[nginx-limit-req]
enabled = true
port = http,https
logpath = $NGINX_LOG_DIR/error.log
maxretry = 10
findtime = 10m
bantime = 1h

EOF
  log "✓ nginx-limit-req jail configured"
fi

# nginx-botsearch: Ban known malicious bots and scanners
if ! sudo grep -q "^\[nginx-botsearch\]" /etc/fail2ban/jail.local; then
  sudo tee -a /etc/fail2ban/jail.local > /dev/null <<EOF

[nginx-botsearch]
enabled = true
port = http,https
logpath = $NGINX_LOG_DIR/access.log
maxretry = 2
findtime = 10m
bantime = 24h

EOF
  log "✓ nginx-botsearch jail configured"
fi

# nginx-bad-request: Ban malformed HTTP requests
if ! sudo grep -q "^\[nginx-bad-request\]" /etc/fail2ban/jail.local; then
  sudo tee -a /etc/fail2ban/jail.local > /dev/null <<EOF

[nginx-bad-request]
enabled = true
port = http,https
logpath = $NGINX_LOG_DIR/access.log
maxretry = 3
findtime = 10m
bantime = 1h

EOF
  log "✓ nginx-bad-request jail configured"
fi

# Ensure nginx log directory exists and is readable
if [ ! -d "$NGINX_LOG_DIR" ]; then
  log "⚠ Warning: nginx logs directory does not exist: $NGINX_LOG_DIR"
  log "  Creating directory..."
  mkdir -p "$NGINX_LOG_DIR"
  chmod 755 "$NGINX_LOG_DIR"
fi

# Test fail2ban configuration
log "Testing fail2ban configuration..."
if sudo fail2ban-client --test > /dev/null 2>&1; then
  log "✓ Configuration test passed"
else
  log "✗ Configuration test failed"
  log "  Run: sudo fail2ban-client --test"
  exit 1
fi

# Enable and start fail2ban service
log "Enabling and starting fail2ban service..."
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban

# Wait for service to start
sleep 2

# Verify service is running
if sudo systemctl is-active --quiet fail2ban; then
  log "✓ Fail2ban service is running"
else
  log "✗ Fail2ban service failed to start"
  log "  Check logs: sudo journalctl -u fail2ban -n 50"
  exit 1
fi

# Display active jails
log ""
log "Active fail2ban jails:"
sudo fail2ban-client status | grep "Jail list" || true

log ""
log "✓ Fail2ban setup completed successfully"
log ""
log "Useful commands:"
log "  Check status:        sudo fail2ban-client status"
log "  Check specific jail: sudo fail2ban-client status sshd"
log "  Unban IP:           sudo fail2ban-client unban <IP>"
log "  View logs:          sudo journalctl -u fail2ban -f"
