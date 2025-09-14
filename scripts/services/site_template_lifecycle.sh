#!/bin/bash
# JStack Site Template Lifecycle Script
# Location: scripts/services/site_template_lifecycle.sh
# Supports: create, list, update, delete, and deploy site templates

set -e

## Removed SITE_TEMPLATES_DIR reference
LOG_DIR="$(dirname "$0")/../../logs"

usage() {
  echo "Usage: $0 [create|add|list|update|delete|remove|deploy|validate_env|validate_compose] <template_name> [options]"
  exit 1
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/site_template_lifecycle.log"
}

create_template() {
  NAME="$1"
  TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$NAME"
  if [ -d "$TEMPLATE_PATH" ]; then
    log "Template $NAME already exists."
    exit 2
  fi
  mkdir -p "$TEMPLATE_PATH"
  echo "# $NAME Site Template" > "$TEMPLATE_PATH/README.md"
  log "Created site template: $NAME"
}

list_templates() {
  log "Listing site templates:"
  ls -1 "$SITE_TEMPLATES_DIR"
}

update_template() {
  NAME="$1"
  TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$NAME"
  if [ ! -d "$TEMPLATE_PATH" ]; then
    log "Template $NAME does not exist."
    exit 2
  fi
  # Placeholder for update logic
  log "Update logic for $NAME not implemented."
}

delete_template() {
  NAME="$1"
  TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$NAME"
  if [ ! -d "$TEMPLATE_PATH" ]; then
    log "Template $NAME does not exist."
    exit 2
  fi
  rm -rf "$TEMPLATE_PATH"
  log "Deleted site template: $NAME"
}

deploy_template() {
  NAME="$1"
  TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$NAME"
  if [ ! -d "$TEMPLATE_PATH" ]; then
    log "Template $NAME does not exist."
    exit 2
  fi
  # Deploy site using docker-compose if compose file exists
  if [ -f "$TEMPLATE_PATH/docker-compose.yml" ]; then
    log "Deploying site template $NAME via docker-compose..."
    docker-compose -f "$TEMPLATE_PATH/docker-compose.yml" up -d
    log "Site template $NAME deployed."
  else
    log "No docker-compose.yml found for $NAME. Cannot deploy."
    exit 2
  fi
}

main() {
  CMD="$1"; shift
  case "$CMD" in
    create|add)
      create_template "$1"
      ;;
    list)
      list_templates
      ;;
    update)
      update_template "$1"
      ;;
    delete|remove)
      delete_template "$1"
      ;;
    deploy)
      deploy_template "$1"
      ;;
    validate_env)
      NAME="$1"
      TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$NAME"
      if [ -f "$TEMPLATE_PATH/.env" ]; then
        log "Env file exists for $NAME"
      else
        log "Env file missing for $NAME"
        exit 2
      fi
      ;;
    validate_compose)
      NAME="$1"
      TEMPLATE_PATH="$SITE_TEMPLATES_DIR/$NAME"
      if [ -f "$TEMPLATE_PATH/docker-compose.yml" ]; then
        log "Compose file exists for $NAME"
      else
        log "Compose file missing for $NAME"
        exit 2
      fi
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
