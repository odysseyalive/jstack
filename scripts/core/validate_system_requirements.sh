#!/bin/bash
# JStack System Requirements Validation Script
# Usage: validate_system_requirements.sh

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Minimum requirements
MIN_CPU_CORES=2
MIN_RAM_MB=2048
MIN_DISK_MB=10240
MIN_NET_MBPS=10

# CPU
CPU_CORES=$(nproc)
if [ "$CPU_CORES" -lt "$MIN_CPU_CORES" ]; then
  log "Insufficient CPU cores: $CPU_CORES (minimum $MIN_CPU_CORES)"
else
  log "CPU cores OK: $CPU_CORES"
fi

# RAM
RAM_MB=$(free -m | awk '/^Mem:/ { print $2 }')
if [ "$RAM_MB" -lt "$MIN_RAM_MB" ]; then
  log "Insufficient RAM: $RAM_MB MB (minimum $MIN_RAM_MB MB)"
else
  log "RAM OK: $RAM_MB MB"
fi

# Disk
DISK_MB=$(df / | tail -1 | awk '{print $4}')
if [ "$DISK_MB" -lt "$MIN_DISK_MB" ]; then
  log "Insufficient disk space: $DISK_MB MB (minimum $MIN_DISK_MB MB)"
else
  log "Disk space OK: $DISK_MB MB"
fi

# Network (simple check: ping google)
PING_TIME=$(ping -c 1 google.com | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}')
if [ -z "$PING_TIME" ]; then
  log "Network check failed."
else
  log "Network latency: $PING_TIME ms"
fi

log "System requirements validation completed."
