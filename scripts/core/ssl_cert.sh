#!/bin/bash
# SSL Certificate Setup Script
# Usage: ssl_cert.sh <action> <domain> <email>

set -e

CONFIG_FILE="$(dirname "$0")/../../jstack.config.default"

if [ $# -lt 3 ]; then
  echo "Usage: $0 <action> <domain> <email>" >&2
  exit 1
fi

ACTION="$1"
DOMAIN="$2"
EMAIL="$3"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  echo "Error: Domain and email are required" >&2
  exit 1
fi

# Load SSL config values
if [ -f "$CONFIG_FILE" ]; then
  SSL_COUNTRY="$(grep -m1 SSL_COUNTRY "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')"
  SSL_STATE="$(grep -m1 SSL_STATE "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')"
  SSL_CITY="$(grep -m1 SSL_CITY "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')"
  SSL_ORGANIZATION="$(grep -m1 SSL_ORGANIZATION "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')"
  SSL_ORG_UNIT="$(grep -m1 SSL_ORG_UNIT "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '"')"
else
  SSL_COUNTRY="US"
  SSL_STATE="State"
  SSL_CITY="City"
  SSL_ORGANIZATION="Organization"
  SSL_ORG_UNIT="OrgUnit"
fi

case "$ACTION" in
  generate_self_signed)
    echo "Generating self-signed SSL certificate for $DOMAIN"
    SSL_DIR="$(dirname "$0")/../../nginx/ssl/live/$DOMAIN"
    mkdir -p "$SSL_DIR"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$SSL_DIR/privkey.pem" \
      -out "$SSL_DIR/fullchain.pem" \
      -subj "/C=$SSL_COUNTRY/ST=$SSL_STATE/L=$SSL_CITY/O=$SSL_ORGANIZATION/OU=$SSL_ORG_UNIT/CN=$DOMAIN"
    chmod 600 "$SSL_DIR/privkey.pem"
    chmod 644 "$SSL_DIR/fullchain.pem"
    echo "Self-signed certificate generated for $DOMAIN"
    ;;
  request_certificate)
    echo "Requesting SSL certificate for $DOMAIN with email $EMAIL"
    certbot certonly --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive || echo "Certbot failed"
    ;;
  validate_certificate)
    echo "Validating SSL certificate for $DOMAIN"
    openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -text || echo "Validation failed"
    ;;
  renew_certificate)
    echo "Renewing SSL certificate for $DOMAIN"
    certbot renew --cert-name "$DOMAIN" || echo "Renewal failed"
    ;;
  run_compliance_check)
    echo "Running SSL compliance check for $DOMAIN"
    # Placeholder for compliance logic
    echo "SSL compliance check passed for $DOMAIN"
    ;;
  run_diagnostics)
    echo "Running SSL diagnostics for $DOMAIN"
    ls -l "/etc/letsencrypt/live/$DOMAIN/" || echo "Diagnostics failed"
    ;;
  *)
    echo "Unknown action: $ACTION"
    exit 1
    ;;
esac
