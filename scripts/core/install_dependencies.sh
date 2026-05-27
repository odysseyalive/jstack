#!/bin/bash
# JStack Dependency Installation Script
# Usage: install_dependencies.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_sudo() {
  if ! sudo -n true 2>/dev/null; then
    log "Error: This script requires sudo access. Please run 'sudo -v' first or add your user to sudoers."
    exit 1
  fi
}

check_docker_group() {
  if ! groups | grep -q docker; then
    log "Warning: User not in docker group. Adding user to docker group..."
    sudo usermod -aG docker "$USER"
    log "User added to docker group. You may need to log out and back in for changes to take effect."
    log "Or run: newgrp docker"
  fi
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

log "Checking prerequisites..."
check_sudo

# Docker
install_if_missing "Docker" "docker" "apt-get update && apt-get install -y docker.io"
check_docker_group

# Docker Compose v2 (plugin). Note: the legacy `docker-compose` (v1 Python)
# package is broken with current Docker images — do NOT install it. v2 is
# invoked as `docker compose` (two words) and ships as the
# `docker-compose-plugin` apt package on Debian/Ubuntu.
if ! docker compose version >/dev/null 2>&1; then
  log "Docker Compose v2 not found. Installing docker-compose-plugin..."
  sudo bash -c "apt-get update && apt-get install -y docker-compose-plugin"
  log "Docker Compose v2 installed."
else
  log "Docker Compose v2 already installed."
fi

# Certbot (for SSL certificate management)
install_if_missing "Certbot" "certbot" "apt-get update && apt-get install -y certbot"

# OpenSSL (for generating secure keys and certificates)
install_if_missing "OpenSSL" "openssl" "apt-get update && apt-get install -y openssl"

# Setup iptables rules for Docker port routing
# DISABLED: Docker now binds directly to ports 80/443 (no port forwarding needed)
# setup_iptables_rules() {
#   log "Setting up iptables rules for Docker port routing..."
#
#   # Allow Docker to bind to privileged ports by routing them to unprivileged ports
#   # Route host port 80 to Docker container port 8080
#   sudo iptables -t nat -C PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null || \
#     sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
#
#   # Route host port 443 to Docker container port 8443
#   sudo iptables -t nat -C PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443 2>/dev/null || \
#     sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8443
#
#   # Save iptables rules so they persist after reboot
#   if command -v iptables-save >/dev/null 2>&1; then
#     sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null 2>&1 || true
#   fi
#
#   # Install iptables-persistent to restore rules on boot
#   if ! dpkg -l | grep -q iptables-persistent; then
#     log "Installing iptables-persistent for rule persistence..."
#     sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
#   fi
#
#   log "✓ iptables rules configured for Docker port routing"
# }
#
# setup_iptables_rules

log "Dependency installation completed."
