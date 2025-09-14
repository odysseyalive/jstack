#!/bin/bash
# UserConfig Management Script
# Usage: user_config.sh <action> <config_path>

set -e
ACTION="$1"
CONFIG_PATH="$2"

case "$ACTION" in
  read_config)
    echo "Reading config from $CONFIG_PATH"
    cat "$CONFIG_PATH"
    ;;
  validate_config)
    echo "Validating config at $CONFIG_PATH"
    # Basic validation: check required fields
    grep -q "DOMAIN=" "$CONFIG_PATH" && grep -q "EMAIL=" "$CONFIG_PATH" && echo "Config valid" || echo "Config invalid"
    ;;
  apply_config)
    echo "Applying config from $CONFIG_PATH"
    source "$CONFIG_PATH"
    ;;
  select_templates)
    echo "Selecting templates from $CONFIG_PATH"
    source "$CONFIG_PATH"
    echo "$TEMPLATES"
    ;;
  set_dry_run)
    echo "Setting dry-run in $CONFIG_PATH"
    sed -i 's/^DRY_RUN=.*/DRY_RUN=true/' "$CONFIG_PATH"
    ;;
  set_backup)
    echo "Setting backup in $CONFIG_PATH"
    sed -i 's/^BACKUP_ENABLED=.*/BACKUP_ENABLED=true/' "$CONFIG_PATH"
    ;;
  *)
    echo "Unknown action: $ACTION"
    exit 1
    ;;
esac
