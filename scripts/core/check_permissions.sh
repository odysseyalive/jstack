#!/bin/bash
# JStack Permission and Sudo Check Script
# Usage: check_permissions.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Checking user permissions..."

if [ "$EUID" -eq 0 ]; then
  log "Running as root."
else
  log "Running as user: $USER"
  if sudo -n true 2>/dev/null; then
    log "User $USER has passwordless sudo access."
  else
    log "User $USER does not have passwordless sudo. Prompting for elevation..."
    sudo -v || { log "Sudo elevation failed. Exiting."; exit 1; }
    log "Sudo elevation successful."
  fi
fi

# Check Docker group membership
if groups | grep -qw docker; then
  log "User $USER is in the docker group."
else
  log "User $USER is not in the docker group. Adding..."
  sudo usermod -aG docker "$USER"
  log "User $USER added to docker group. You may need to log out and back in."
fi

# Check NGINX access
if sudo systemctl status nginx >/dev/null 2>&1; then
  log "NGINX is installed and accessible."
else
  log "NGINX is not installed or not accessible."
fi

# Check Certbot access
if command -v certbot >/dev/null 2>&1; then
  log "Certbot is installed."
else
  log "Certbot is not installed."
fi

# Check Fail2ban access
if sudo systemctl status fail2ban >/dev/null 2>&1; then
  log "Fail2ban is installed and accessible."
else
  log "Fail2ban is not installed or not accessible."
fi

log "Permission and sudo checks completed."
