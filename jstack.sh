#!/bin/bash
# JStack Entrypoint Script
# Usage: jstack.sh [--dry-run|--backup|--reset|--uninstall|--repair|--debug] <action> [args]

set -e

CONFIG_FILE="$(dirname "$0")/jstack.config.default"
SCRIPTS_CORE="$(dirname "$0")/scripts/core"
SCRIPTS_SERVICES="$(dirname "$0")/scripts/services"

show_usage() {
  echo "Usage: $0 [--dry-run|--install|--backup|--reset|--uninstall|--repair|--debug|--cert-fix|--install-site <site_dir>] <action> [args]"
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
  CERT_FIX=false
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
    --cert-fix) CERT_FIX=true ;;
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
    run_core_script orchestrate down nginx
    sudo certbot certonly --standalone -d "$DOMAIN" --agree-tos --non-interactive --email "$EMAIL"
    run_core_script orchestrate up nginx
    exit $?
  fi
  if [ "$CERT_FIX" = true ]; then
    echo "Running SSL certificate fix..."
    CONFIG_FILE="$(dirname "$0")/jstack.config"
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    
    # Step 1: Create simplified nginx configs for ACME challenge only
    echo "Creating temporary nginx configs for ACME challenges..."
    NGINX_CONF_DIR="./nginx/conf.d"
    
    # Backup existing configs
    mkdir -p ./nginx/conf.d.backup
    cp -r ./nginx/conf.d/* ./nginx/conf.d.backup/ 2>/dev/null || true
    
    # Create minimal config for ACME challenges
    cat > "$NGINX_CONF_DIR/acme-only.conf" <<'EOF'
# Temporary config for ACME challenges only
server {
    listen 8080 default_server;
    server_name _;
    
    # ACME challenge location for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }
    
    # Redirect all other traffic to a simple response
    location / {
        return 200 "ACME validation server";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Remove other configs temporarily
    find "$NGINX_CONF_DIR" -name "*.conf" ! -name "acme-only.conf" -delete
    
    # Step 2: Start nginx with minimal config
    echo "Starting nginx with ACME-only configuration..."
    docker-compose restart nginx
    
    # Step 3: Wait for nginx to be ready
    echo "Waiting for nginx to start..."
    sleep 15
    
    # Step 4: Test ACME path
    echo "Testing ACME challenge path..."
    mkdir -p ./nginx/certbot/www/.well-known/acme-challenge
    echo "test-challenge" > ./nginx/certbot/www/.well-known/acme-challenge/test
    
    # Step 5: Get SSL certificates using webroot method
    echo "Attempting to get SSL certificates..."
    for SUBDOMAIN in "api.$DOMAIN" "n8n.$DOMAIN" "studio.$DOMAIN" "chrome.$DOMAIN"; do
      echo "Getting SSL certificate for $SUBDOMAIN..."
      if sudo certbot certonly --webroot -w ./nginx/certbot/www -d "$SUBDOMAIN" --agree-tos --non-interactive --email "$EMAIL"; then
        echo "✓ SSL certificate obtained for $SUBDOMAIN"
      else
        echo "⚠ Failed to get SSL certificate for $SUBDOMAIN"
      fi
    done
    
    # Step 6: Restore original nginx configs
    echo "Restoring original nginx configurations..."
    rm -f "$NGINX_CONF_DIR/acme-only.conf"
    cp -r ./nginx/conf.d.backup/* "$NGINX_CONF_DIR/" 2>/dev/null || true
    rm -rf ./nginx/conf.d.backup
    
    # Step 7: Start all services and restart nginx with full config
    echo "Starting all services with full configuration..."
    docker-compose up -d
    sleep 30
    docker-compose restart nginx
    
    echo "SSL certificate fix completed."
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
      
      # Use our robust SSL system to generate config and handle SSL
      source "$(dirname "$0")/scripts/core/setup_service_subdomains_ssl.sh"
      
      # Generate nginx config for the site
      if generate_site_nginx_config "$SITE_DOMAIN" "$SITE_PORT" "$SITE_CONTAINER"; then
        echo "✓ Nginx config created for $SITE_DOMAIN"
        
        # Add domain to SSL certificate
        if install_site_ssl_certificate "$SITE_DOMAIN"; then
          echo "✓ SSL certificate configured for $SITE_DOMAIN"
        else
          echo "⚠ SSL setup failed, but site will work with certificate warnings"
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
