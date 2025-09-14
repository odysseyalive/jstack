#!/bin/bash
# JStack Fail2ban Setup Script
# Usage: setup_fail2ban.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Setting up Fail2ban for SSH and NGINX security..."

# Enable and start Fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Configure Fail2ban for SSH
if [ -f "/etc/fail2ban/jail.local" ]; then
  sudo sed -i '/\[sshd\]/,/^$/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
else
  echo -e "[sshd]\nenabled = true" | sudo tee -a /etc/fail2ban/jail.local > /dev/null
fi
log "Fail2ban SSH jail enabled."

# Configure Fail2ban for NGINX
if [ -f "/etc/fail2ban/jail.local" ]; then
  if ! grep -q "[nginx-http-auth]" /etc/fail2ban/jail.local; then
    echo -e "[nginx-http-auth]\nenabled = true\nfilter = nginx-http-auth\naction = iptables[name=NoAuthFailures, port=http, protocol=tcp]\nlogpath = /var/log/nginx/error.log\nmaxretry = 3" | sudo tee -a /etc/fail2ban/jail.local > /dev/null
    log "Fail2ban NGINX jail added."
  fi
fi

sudo systemctl restart fail2ban
log "Fail2ban setup and configuration completed."
