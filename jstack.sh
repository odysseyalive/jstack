#!/bin/bash
# JStack Entrypoint Script
# Usage: jstack.sh [--dry-run|--backup|--reset|--uninstall|--repair|--debug] <action> [args]

set -e

CONFIG_FILE="$(dirname "$0")/jstack.config.default"
SCRIPTS_CORE="$(dirname "$0")/scripts/core"
SCRIPTS_SERVICES="$(dirname "$0")/scripts/services"

show_usage() {
  echo "Usage: $0 [--dry-run|--backup|--reset|--uninstall|--repair|--debug|--install-site <site_dir>] <action> [args]"
  echo "Actions: up, down, restart, status, backup, restore, validate, propagate, diagnostics, compliance, monitor, template, launch"
  exit 1
}

parse_flags() {
  DRY_RUN=false
  BACKUP=false
  RESET=false
  UNINSTALL=false
  REPAIR=false
  DEBUG=false
  INSTALL_SITE=""
  while [[ "$1" == --* ]]; do
    case "$1" in
    --dry-run) DRY_RUN=true ;;
    --backup) BACKUP=true ;;
    --reset) RESET=true ;;
    --uninstall) UNINSTALL=true ;;
    --repair) REPAIR=true ;;
    --debug) DEBUG=true ;;
    --install-site)
      shift
      INSTALL_SITE="$1"
      ;;
    *) show_usage ;;
    esac
    shift
  done
  ACTION="$1"
  shift
  ARGS=("$@")
}

run_core_script() {
  SCRIPT="$1"
  shift
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would run: $SCRIPT $@"
  else
    bash "$SCRIPTS_CORE/$SCRIPT.sh" "$@"
  fi
}

run_service_script() {
  SCRIPT="$1"
  shift
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would run: $SCRIPT $@"
  else
    bash "$SCRIPTS_SERVICES/$SCRIPT.sh" "$@"
  fi
}

main() {
  parse_flags "$@"
  if [ -n "$INSTALL_SITE" ]; then
    # Integrated site install workflow
    SITE_DIR="$INSTALL_SITE"
    if [ ! -d "$SITE_DIR" ]; then
      echo "Site directory $SITE_DIR does not exist."
      exit 2
    fi
    # Prompt user for DB credentials securely
    if [ -z "$DBUSER" ]; then
      read -r -p "Enter new MariaDB username: " DBUSER
    fi
    if [ -z "$DBPASS" ]; then
      read -r -s -p "Enter new MariaDB password: " DBPASS
      echo
    fi
    export DBUSER
    export DBPASS
    # Deploy site via docker-compose
    if [ -f "$SITE_DIR/docker-compose.yml" ]; then
      if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Would run: DBUSER=**** DBPASS=**** docker-compose -f $SITE_DIR/docker-compose.yml up -d"
      else
        DBUSER="$DBUSER" DBPASS="$DBPASS" docker-compose -f "$SITE_DIR/docker-compose.yml" up -d
      fi
    else
      echo "No docker-compose.yml found in $SITE_DIR."
      exit 2
    fi
    # Add NGINX config
    NGINX_CONF="nginx.conf"
    SITE_DOMAIN="$(grep -m1 DOMAIN "$SITE_DIR/.env" | cut -d'=' -f2)"
    SITE_PORT="$(grep -m1 PORT "$SITE_DIR/.env" | cut -d'=' -f2)"
    if [ -z "$SITE_DOMAIN" ] || [ -z "$SITE_PORT" ]; then
      echo "Missing DOMAIN or PORT in $SITE_DIR/.env."
      exit 2
    fi
    NGINX_ENTRY="\nserver {\n    listen 443;\n    server_name $SITE_DOMAIN;\n    location / {\n        proxy_pass http://127.0.0.1:$SITE_PORT;\n    }\n}"
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY-RUN] Would append NGINX config for $SITE_DOMAIN to $NGINX_CONF:"
      echo -e "$NGINX_ENTRY"
      echo "[DRY-RUN] Would reload NGINX."
      echo "[DRY-RUN] Would request SSL certificate for $SITE_DOMAIN with Certbot."
    else
      echo -e "$NGINX_ENTRY" | sudo tee -a "$NGINX_CONF" >/dev/null
      sudo nginx -s reload
      echo "NGINX config updated and reloaded for $SITE_DOMAIN."
      EMAIL="$(grep -m1 EMAIL jstack.config.default | cut -d'=' -f2)"
      if [ -n "$EMAIL" ]; then
        sudo certbot --nginx -d "$SITE_DOMAIN" --non-interactive --agree-tos --email "$EMAIL" || echo "Certbot failed for $SITE_DOMAIN."
        echo "SSL certificate requested for $SITE_DOMAIN."
      else
        echo "No EMAIL found in jstack.config.default, skipping Certbot."
      fi
    fi
    echo "Site $SITE_DOMAIN installed from $SITE_DIR."
    exit 0
  fi
  case "$ACTION" in
  up | down | restart | status)
    run_core_script orchestrate "$ACTION" "${ARGS[@]}"
    ;;
  backup | restore)
    run_core_script backup_restore "$ACTION" "${ARGS[@]}"
    ;;
  validate)
    run_core_script config_validator validate
    ;;
  propagate)
    run_core_script config_validator propagate
    ;;
  diagnostics)
    run_core_script diagnostics "${ARGS[@]}"
    ;;
  compliance)
    run_core_script compliance "${ARGS[@]}"
    ;;
  monitor)
    run_core_script monitor "${ARGS[@]}"
    ;;
  template)
    run_service_script site_template_lifecycle "${ARGS[@]}"
    ;;
  launch)
    # Launch a new site using a template
    TEMPLATE_NAME="${ARGS[0]}"
    run_service_script site_template_lifecycle deploy "$TEMPLATE_NAME"
    ;;
  *)
    show_usage
    ;;
  esac
}

main "$@"
