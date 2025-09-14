#!/bin/bash
# JStack Monitoring Workflow Integration Script
# Usage: monitor.sh [diagnostics|compliance|health] <service_name>

set -e

DIAGNOSTICS_SCRIPT="$(dirname "$0")/diagnostics.sh"
COMPLIANCE_SCRIPT="$(dirname "$0")/compliance.sh"

usage() {
  echo "Usage: $0 [diagnostics|compliance|health] <service_name>"
  exit 1
}

main() {
  if [ $# -eq 0 ]; then
    show_usage
  fi
  ACTION="$1"; shift
  SERVICE="$1"
  case "$ACTION" in
    diagnostics)
      bash "$DIAGNOSTICS_SCRIPT" "$SERVICE"
      ;;
    compliance)
      bash "$COMPLIANCE_SCRIPT" "$SERVICE"
      ;;
    health)
      bash "$DIAGNOSTICS_SCRIPT" "$SERVICE"
      # Optionally add more health check logic here
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
