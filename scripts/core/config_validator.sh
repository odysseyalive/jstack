#!/bin/bash
# JStack Config Validation and Propagation Script
# Usage: config_validator.sh [validate|propagate]

set -e

CONFIG_FILE="$(dirname "$0")/../../jstack.config.default"
## Removed SITE_TEMPLATES_DIR reference

usage() {
  echo "Usage: $0 [validate|propagate]"
  exit 1
}

validate_config() {
  echo "Validating $CONFIG_FILE..."
  REQUIRED_FIELDS=(DOMAIN EMAIL NGINX_PORT SUPABASE_PORT N8N_PORT CHROME_PORT SUPABASE_DB SUPABASE_USER SUPABASE_PASSWORD N8N_ENV N8N_BASIC_AUTH_USER N8N_BASIC_AUTH_PASSWORD)
  for field in "${REQUIRED_FIELDS[@]}"; do
    if ! grep -q "^$field=" "$CONFIG_FILE"; then
      echo "Config missing required field: $field"
      exit 2
    fi
  done
  echo "Config validation passed."
}

propagate_config() {
  echo "Propagating config to site templates..."
  for template in $(grep '^TEMPLATES=' "$CONFIG_FILE" | cut -d'=' -f2 | tr ',' ' '); do
    TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$template/.env"
    if [ -d "$SITE_TEMPLATES_DIR/$template" ]; then
      cp "$CONFIG_FILE" "$TEMPLATE_PATH"
      echo "Config propagated to $TEMPLATE_PATH"
    else
      echo "Template $template does not exist, skipping propagation."
    fi
  done
}

main() {
  ACTION="$1"
  case "$ACTION" in
    validate)
      validate_config
      ;;
    propagate)
      propagate_config
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
