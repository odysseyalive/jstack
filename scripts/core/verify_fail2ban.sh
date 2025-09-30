#!/bin/bash
# JStack Fail2ban Verification Script
# Usage: verify_fail2ban.sh
#
# Verifies that fail2ban is properly installed and configured

set -e

WORKSPACE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NGINX_LOG_DIR="$WORKSPACE_ROOT/nginx/logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1"
}

success() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1"
}

ERRORS=0

log "Starting fail2ban verification..."
echo ""

# Check 1: Is fail2ban installed?
log "=== Check 1: Installation ==="
if command -v fail2ban-server >/dev/null 2>&1; then
  VERSION=$(fail2ban-server --version 2>&1 | head -n1)
  success "Fail2ban is installed: $VERSION"
else
  error "Fail2ban is not installed"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 2: Is fail2ban service running?
log "=== Check 2: Service Status ==="
if sudo systemctl is-active --quiet fail2ban 2>/dev/null; then
  success "Fail2ban service is running"
  sudo systemctl status fail2ban --no-pager | grep "Active:"
else
  error "Fail2ban service is not running"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 3: Configuration files exist?
log "=== Check 3: Configuration Files ==="
if [ -f "/etc/fail2ban/jail.local" ]; then
  success "jail.local exists"
  JAILS=$(grep -c "^\[.*\]" /etc/fail2ban/jail.local || echo "0")
  log "  Found $JAILS jail sections configured"
else
  error "jail.local does not exist"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 4: Are expected jails enabled?
log "=== Check 4: Configured Jails ==="
EXPECTED_JAILS=("sshd" "nginx-http-auth" "nginx-limit-req" "nginx-botsearch" "nginx-bad-request")
for JAIL in "${EXPECTED_JAILS[@]}"; do
  if sudo grep -q "^\[$JAIL\]" /etc/fail2ban/jail.local 2>/dev/null; then
    if sudo grep -A5 "^\[$JAIL\]" /etc/fail2ban/jail.local | grep -q "enabled = true"; then
      success "$JAIL jail is configured and enabled"
    else
      error "$JAIL jail exists but is not enabled"
      ERRORS=$((ERRORS + 1))
    fi
  else
    error "$JAIL jail is not configured"
    ERRORS=$((ERRORS + 1))
  fi
done
echo ""

# Check 5: Are jails actually running?
log "=== Check 5: Active Jails ==="
if command -v fail2ban-client >/dev/null 2>&1; then
  ACTIVE_JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list:" | sed 's/.*://;s/,//g' || echo "")
  if [ -n "$ACTIVE_JAILS" ]; then
    success "Active jails: $ACTIVE_JAILS"

    # Show details for each active jail
    for JAIL in $ACTIVE_JAILS; do
      log ""
      log "  Details for jail: $JAIL"
      sudo fail2ban-client status "$JAIL" 2>/dev/null | sed 's/^/    /' || error "    Failed to get status for $JAIL"
    done
  else
    error "No jails are currently active"
    ERRORS=$((ERRORS + 1))
  fi
else
  error "fail2ban-client not available"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 6: Nginx log files accessible?
log "=== Check 6: Log Files ==="
if [ -d "$NGINX_LOG_DIR" ]; then
  success "Nginx logs directory exists: $NGINX_LOG_DIR"

  if [ -f "$NGINX_LOG_DIR/access.log" ]; then
    success "access.log exists"
    SIZE=$(du -h "$NGINX_LOG_DIR/access.log" | cut -f1)
    log "  Size: $SIZE"
  else
    error "access.log does not exist (will be created when nginx receives traffic)"
  fi

  if [ -f "$NGINX_LOG_DIR/error.log" ]; then
    success "error.log exists"
    SIZE=$(du -h "$NGINX_LOG_DIR/error.log" | cut -f1)
    log "  Size: $SIZE"
  else
    error "error.log does not exist (will be created when nginx logs errors)"
  fi

  # Check if fail2ban can read the logs
  if [ -r "$NGINX_LOG_DIR/access.log" ] || [ -r "$NGINX_LOG_DIR/error.log" ]; then
    success "Fail2ban should be able to read nginx logs"
  else
    error "Log files may not be readable by fail2ban"
    ERRORS=$((ERRORS + 1))
  fi
else
  error "Nginx logs directory does not exist: $NGINX_LOG_DIR"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 7: Test configuration syntax
log "=== Check 7: Configuration Syntax ==="
if sudo fail2ban-client --test >/dev/null 2>&1; then
  success "Configuration syntax is valid"
else
  error "Configuration has syntax errors"
  log "  Run: sudo fail2ban-client --test"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 8: Iptables rules exist?
log "=== Check 8: Firewall Rules ==="
if command -v iptables >/dev/null 2>&1; then
  F2B_CHAINS=$(sudo iptables -L -n 2>/dev/null | grep -c "^Chain f2b-" || echo "0")
  if [ "$F2B_CHAINS" -gt 0 ]; then
    success "Found $F2B_CHAINS fail2ban iptables chains"
    sudo iptables -L -n 2>/dev/null | grep "^Chain f2b-" | sed 's/^/  /'
  else
    error "No fail2ban iptables chains found (may not have banned any IPs yet)"
  fi
else
  error "iptables command not available"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# Summary
log "=== Verification Summary ==="
if [ $ERRORS -eq 0 ]; then
  success "All checks passed! Fail2ban is properly configured and running."
  echo ""
  log "Useful commands:"
  log "  Check status:        sudo fail2ban-client status"
  log "  Check specific jail: sudo fail2ban-client status sshd"
  log "  View banned IPs:     sudo fail2ban-client banned"
  log "  Unban IP:           sudo fail2ban-client unban <IP>"
  log "  View logs:          sudo journalctl -u fail2ban -f"
  log "  Test regex:         fail2ban-regex <logfile> <filter>"
  exit 0
else
  error "Verification completed with $ERRORS error(s)"
  echo ""
  log "Common troubleshooting steps:"
  log "  1. Check service logs:     sudo journalctl -u fail2ban -n 50"
  log "  2. Test configuration:     sudo fail2ban-client --test"
  log "  3. Restart service:        sudo systemctl restart fail2ban"
  log "  4. Check log permissions:  ls -la $NGINX_LOG_DIR"
  exit 1
fi
