#!/bin/bash
# JStack Config Validation Script
# Usage: config_validator.sh [validate]

set -e

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Validate the config the stack actually uses: jstack.config when the operator has one,
# else the jstack.config.default template. Until 2026-09-19 this was hardcoded to the
# template, so `jstack.sh validate` validated a file nothing reads and could not fail
# for the reason it exists.
# shellcheck source=scripts/core/jstack_config.sh
. "$REPO_ROOT/scripts/core/jstack_config.sh"
CONFIG_FILE="$(_jstack_config_file)"

usage() {
  echo "Usage: $0 [validate]"
  exit 1
}

validate_config() {
  echo "Validating $CONFIG_FILE..."
  REQUIRED_FIELDS=(DOMAIN EMAIL NGINX_PORT)
  for field in "${REQUIRED_FIELDS[@]}"; do
    if ! grep -q "^$field=" "$CONFIG_FILE"; then
      echo "Config missing required field: $field"
      exit 2
    fi
  done
  echo "Config validation passed."
}

# propagate_config() was removed on 2026-09-19. It looped over a TEMPLATES= key that
# neither jstack.config nor jstack.config.default has ever defined, so the loop ran zero
# times; its body copied into $SITE_TEMPLATES_DIR, a variable this file had already had
# removed (the "## Removed SITE_TEMPLATES_DIR reference" marker that used to sit on line
# 8), so the body was unreachable and would have written to /<template>/.env if it were
# reachable. `propagate` printed "Propagating config to site templates..." and exited 0
# having done nothing. It fails loudly now; see the propagate) arm in main().

main() {
  ACTION="$1"
  case "$ACTION" in
    validate)
      validate_config
      ;;
    propagate)
      echo "ERROR: the 'propagate' action no longer exists." >&2
      echo "It copied the config into site-template .env files through a TEMPLATES= key that no jstack config defines, so it never copied anything and exited 0 anyway." >&2
      exit 1
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
