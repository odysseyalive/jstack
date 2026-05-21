#!/bin/bash
# JStack Entrypoint Script
# Usage: jstack.sh [--dry-run|--backup|--reset|--uninstall|--repair|--debug] <action> [args]

set -e

CONFIG_FILE="$(dirname "$0")/jstack.config.default"
SCRIPTS_CORE="$(dirname "$0")/scripts/core"
SCRIPTS_SERVICES="$(dirname "$0")/scripts/services"

show_usage() {
  echo "Usage: $0 [flags] <action> [args]"
  echo ""
  echo "Flags:"
  echo "  --install                       Run core install (nginx + certbot + base-domain cert)"
  echo "  --install-site <site_dir>       Deploy a site container behind nginx + SSL"
  echo "  --dry-run|--backup|--reset|--uninstall|--repair|--debug"
  echo ""
  echo "Actions: up, down, restart, status, deploy, backup, restore, validate, propagate, diagnostics, compliance, monitor, template, launch"
  echo "Deploy: deploy <site-domain>  - Restart a site container after rebuild (e.g., deploy odysseyalive.com)"
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
  while [[ "$1" == --* ]]; do
    case "$1" in
    --dry-run) DRY_RUN=true ;;
    --install) INSTALL=true ;;
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
    # Core install: nginx + certbot + base-domain cert
    run_core_script install_dependencies
    run_core_script full_stack_install
    ./jstack.sh up
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
    # Add NGINX config and SSL certificate
    SITE_DOMAIN="$(grep -m1 DOMAIN "$SITE_DIR/.env" | cut -d'=' -f2)"
    SITE_PORT="$(grep -m1 PORT "$SITE_DIR/.env" | cut -d'=' -f2)"
    SITE_CONTAINER="$(grep -m1 CONTAINER "$SITE_DIR/.env" | cut -d'=' -f2 2>/dev/null || echo "")"

    if [ -z "$SITE_DOMAIN" ] || [ -z "$SITE_PORT" ]; then
      echo "Missing DOMAIN or PORT in $SITE_DIR/.env."
      echo "Required format:"
      echo "  DOMAIN=mysite.example.com"
      echo "  PORT=3000"
      echo "  CONTAINER=mysite_app  # optional - uses docker networking if provided"
      exit 2
    fi

    if [ "$DRY_RUN" = true ]; then
      echo "[DRY-RUN] Would generate nginx config for $SITE_DOMAIN (port $SITE_PORT)"
      echo "[DRY-RUN] Would add $SITE_DOMAIN to SSL certificate"
      echo "[DRY-RUN] Would restart nginx container"
    else
      echo "Setting up nginx and SSL for $SITE_DOMAIN..."

      # Use our nginx + SSL helpers
      source "$(dirname "$0")/scripts/core/setup_service_subdomains_ssl.sh"

      # Phase 1: write HTTP-only proxy config (with ACME location) and reload
      if generate_site_nginx_config "$SITE_DOMAIN" "$SITE_PORT" "$SITE_CONTAINER"; then
        echo "✓ HTTP nginx config created for $SITE_DOMAIN"
        docker-compose -f "$(dirname "$0")/docker-compose.yml" exec -T nginx nginx -s reload >/dev/null 2>&1 || true

        # Phase 2: acquire cert for the site domain
        if install_site_ssl_certificate "$SITE_DOMAIN"; then
          # Phase 3: rewrite config to include HTTPS + redirect
          upgrade_site_to_https "$SITE_DOMAIN" "$SITE_PORT" "$SITE_CONTAINER"
          docker-compose -f "$(dirname "$0")/docker-compose.yml" exec -T nginx nginx -s reload >/dev/null 2>&1 || true
          echo "✓ HTTPS enabled for $SITE_DOMAIN"
        else
          echo "⚠ SSL acquisition failed; site stays HTTP-only (re-run --install-site to retry)"
        fi
      else
        echo "ERROR: Failed to generate nginx config for $SITE_DOMAIN"
        exit 1
      fi
    fi
    echo "Site $SITE_DOMAIN installed from $SITE_DIR."
    exit 0
  fi
  case "$ACTION" in
  deploy)
    # Deploy/restart a site container after rebuild
    SITE_NAME="${ARGS[0]}"
    if [ -z "$SITE_NAME" ]; then
      echo "Usage: jstack.sh deploy <site-domain>"
      echo "Example: jstack.sh deploy odysseyalive.com"
      exit 1
    fi
    SITE_DIR="$(dirname "$0")/sites/$SITE_NAME"
    if [ ! -d "$SITE_DIR" ]; then
      echo "Site directory $SITE_DIR does not exist."
      exit 2
    fi
    if [ ! -f "$SITE_DIR/docker-compose.yml" ]; then
      echo "No docker-compose.yml found in $SITE_DIR."
      exit 2
    fi
    echo "Restarting $SITE_NAME..."
    docker-compose -f "$SITE_DIR/docker-compose.yml" restart
    echo "✓ $SITE_NAME deployed"
    ;;
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
