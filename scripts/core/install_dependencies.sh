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

# Docker Compose
install_if_missing "Docker Compose" "docker-compose" "apt-get update && apt-get install -y docker-compose"

# Certbot (for SSL certificate management)
install_if_missing "Certbot" "certbot" "apt-get update && apt-get install -y certbot"

# OpenSSL (for generating secure keys and certificates)
install_if_missing "OpenSSL" "openssl" "apt-get update && apt-get install -y openssl"

log "Dependency installation completed."
