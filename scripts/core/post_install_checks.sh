#!/bin/bash
# JStack Post-Install Health, Diagnostics, and Compliance Script
# Usage: post_install_checks.sh

set -e

SERVICES=(nginx n8n supabase chrome)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

for SERVICE in "${SERVICES[@]}"; do
  log "Running diagnostics for $SERVICE..."
  bash scripts/core/diagnostics.sh "$SERVICE"
  log "Running compliance checks for $SERVICE..."
  bash scripts/core/compliance.sh "$SERVICE"
  log "Health and compliance checks completed for $SERVICE."
done

log "Post-install health, diagnostics, and compliance checks completed."
