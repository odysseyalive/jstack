#!/bin/bash
# Which jstack config file a script reads, and how it loads it. SOURCE THIS — do not run it.
#
# jstack.config.default says so in its own header: "Copied to jstack.config on first
# install. Edit jstack.config (NOT this file) to customize." A script that reads
# jstack.config.default therefore reads the TEMPLATE, and on a configured host that
# yields DOMAIN=example.com and EMAIL=admin@example.com instead of the operator's real
# values. On this host the two files differ in DOMAIN, EMAIL, SSL_CITY and
# SSL_ORGANIZATION and are identical everywhere else, which is why reading the wrong
# one produced plausible output for a long time.
#
# The fallback is not optional: a fresh clone has no jstack.config at all — it is
# written by scripts/core/full_stack_install.sh on first install — so every reader
# needs "the real one if it exists, else the template".
#
# WHY A FILE OF ITS OWN, and not scripts/core/script_module.sh: that file is a CLI
# dispatcher. It sets `set -e` and exits 1 when given fewer than two arguments, so
# sourcing it would terminate the sourcing script. This file follows the same
# source-only construction as scripts/core/nginx_conf_perms.sh: it sets no shell
# options, writes nothing, and runs nothing at source time. It is safe to source under
# `set -e`, `set -u` and `set -o pipefail` alike.
#
# WHY A HELPER RATHER THAN A COPY PER SCRIPT: four scripts need this same answer
# (backup_restore.sh, config_validator.sh, setup_ssl_certbot.sh, and
# setup_service_subdomains_ssl.sh, whose lines 77-85 are where this shape comes from).
# Three of them had it wrong in three different ways. One copy per caller is the thing
# nginx_conf_perms.sh's own header describes going wrong: the copies had already
# diverged before anyone looked.

# The config file a reader should use: jstack.config when it exists, else
# jstack.config.default.
#
#   _jstack_config_file
#
# Takes no arguments on purpose. The repo root is derived from THIS file's own location
# (${BASH_SOURCE[0]} inside a function is the file the function was defined in), so a
# caller cannot pass the wrong root and a caller's working directory does not matter.
_jstack_config_file() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  if [ -f "$root/jstack.config" ]; then
    echo "$root/jstack.config"
  else
    echo "$root/jstack.config.default"
  fi
}

# Load that file's values into the calling shell: DOMAIN, EMAIL, SSL_* and whatever else
# it defines.
#
#   _jstack_load_config
#
# Sourcing rather than grepping is deliberate. `grep -m1 EMAIL file | cut -d= -f2` — the
# shape this replaces in setup_ssl_certbot.sh — matches any line CONTAINING the
# substring, comments included, and keeps the surrounding quotes. It resolved to the
# comment fragment "# to customize. Only DOMAIN and EMAIL are required." See
# .claude/skills/awareness-ledger/ledger/patterns/PAT-2026-09-02-jstack-env-unanchored-grep.md
# for the same defect in jstack.sh, where it silently 502s a site.
#
# The values land as globals even though the `.` runs inside a function: a plain
# assignment in a sourced file touches the global unless that same function declared a
# local of that name, and the only local here is `cfg`.
#
# A config file that exists but does not parse is left to abort the caller under `set
# -e`. That is intended — continuing from a broken config is how a placeholder value
# reaches certbot.
_jstack_load_config() {
  local cfg
  cfg="$(_jstack_config_file)"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
  fi
}
