#!/bin/bash
# JStack Entrypoint Script
# Usage: jstack.sh [--dry-run|--backup|--reset|--uninstall|--repair|--debug] <action> [args]

set -e

CONFIG_FILE="$(dirname "$0")/jstack.config.default"
SCRIPTS_CORE="$(dirname "$0")/scripts/core"
SCRIPTS_SERVICES="$(dirname "$0")/scripts/services"

show_usage() {
  echo "Usage: $0 [--dry-run|--install|--backup|--reset|--uninstall|--repair|--debug|--install-site <site_dir>] <action> [args]"
  echo "Actions: up, down, restart, status, backup, restore, validate, propagate, diagnostics, compliance, monitor, template, launch"
  exit 1
}

parse_flags() {
  DRY_RUN=false
  INSTALL=false
  BACKUP=false
  RESET=false
  UNINSTALL=false
  REPAIR=false
  DEBUG=false
  INSTALL_SITE=""
  CERTBOT=false
  while [[ "$1" == --* ]]; do
    case "$1" in
    --dry-run) DRY_RUN=true ;;
    --install) INSTALL=true ;;
    --backup) BACKUP=true ;;
    --reset) RESET=true ;;
    --uninstall) UNINSTALL=true ;;
    --repair) REPAIR=true ;;
    --debug) DEBUG=true ;;
    --certbot) CERTBOT=true ;;
    --install-site)
      shift
      INSTALL_SITE="$1"
      ;;
    *) show_usage ;;
    esac
    shift
  done
  if [ $# -gt 0 ]; then
    ACTION="$1"
    shift
    ARGS=("$@")
  else
    ACTION=""
    ARGS=()
  fi
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
  if [ "$INSTALL" = true ]; then
    # Full stack installation
    run_core_script install_dependencies
    run_core_script full_stack_install
    ./jstack.sh up
    exit $?
  fi
  if [ "$CERTBOT" = true ]; then
    CONFIG_FILE="$(dirname "$0")/jstack.config"
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    run_core_script orchestrate stop nginx
    sudo certbot certonly --standalone -d "$DOMAIN" --agree-tos --non-interactive --email "$EMAIL"
    run_core_script orchestrate start nginx
    exit $?
  fi
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
    NGINX_CONF="nginx/conf.d/${SITE_DOMAIN}.conf"
    SITE_DOMAIN="$(grep -m1 DOMAIN "$SITE_DIR/.env" | cut -d'=' -f2)"
    SITE_PORT="$(grep -m1 PORT "$SITE_DIR/.env" | cut -d'=' -f2)"
    if [ -z "$SITE_DOMAIN" ] || [ -z "$SITE_PORT" ]; then
      echo "Missing DOMAIN or PORT in $SITE_DIR/.env."
      exit 2
    fi
    NGINX_ENTRY="server {
    listen 443 ssl;
    server_name $SITE_DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$SITE_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$SITE_DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://172.17.0.1:$SITE_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}"
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY-RUN] Would create NGINX config for $SITE_DOMAIN at $NGINX_CONF:"
      echo "$NGINX_ENTRY"
      echo "[DRY-RUN] Would restart nginx container."
      echo "[DRY-RUN] Would request SSL certificate for $SITE_DOMAIN with Certbot."
    else
      echo "$NGINX_ENTRY" > "$NGINX_CONF"
      echo "NGINX config created at $NGINX_CONF for $SITE_DOMAIN."
      # Restart nginx container to reload config
      docker-compose restart nginx
      echo "NGINX container restarted."
      EMAIL="$(grep -m1 EMAIL jstack.config.default | cut -d'=' -f2)"
      if [ -n "$EMAIL" ]; then
        # Create SSL cert directory
        mkdir -p "nginx/ssl/live/$SITE_DOMAIN"
        # Use certbot in standalone mode since nginx is containerized
        sudo certbot certonly --standalone -d "$SITE_DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --cert-path "nginx/ssl/live/$SITE_DOMAIN/" || echo "Certbot failed for $SITE_DOMAIN."
        echo "SSL certificate requested for $SITE_DOMAIN."
        # Restart nginx again to load SSL certs
        docker-compose restart nginx
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
