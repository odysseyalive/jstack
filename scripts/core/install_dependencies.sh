#!/bin/bash
# JStack Dependency Installation Script
# Usage: install_dependencies.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

install_if_missing() {
  PKG="$1"
  CMD="$2"
  INSTALL_CMD="$3"
  if ! command -v "$CMD" >/dev/null 2>&1; then
    log "$PKG not found. Installing..."
    sudo bash -c "$INSTALL_CMD"
    log "$PKG installed."
  else
    log "$PKG already installed."
  fi
}

# Docker
install_if_missing "Docker" "docker" "apt-get update && apt-get install -y docker.io"

# Docker Compose
install_if_missing "Docker Compose" "docker-compose" "apt-get update && apt-get install -y docker-compose"

# NGINX
if ! dpkg -l | grep -qw nginx; then
  log "NGINX not found. Installing..."
  sudo apt-get update && sudo apt-get install -y nginx
  log "NGINX installed."
else
  log "NGINX already installed."
fi

# Certbot
install_if_missing "Certbot" "certbot" "apt-get update && apt-get install -y certbot python3-certbot-nginx"

# Fail2ban
if ! dpkg -l | grep -qw fail2ban; then
  log "Fail2ban not found. Installing..."
  sudo apt-get update && sudo apt-get install -y fail2ban
  log "Fail2ban installed."
else
  log "Fail2ban already installed."
fi

log "Dependency installation completed."
