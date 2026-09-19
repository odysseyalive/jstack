#!/bin/bash
# Ownership and mode for files written into nginx/conf.d. SOURCE THIS — do not run it.
#
# Two scripts write vhosts into nginx/conf.d and both need the same answer to "what
# should this file end up owned by and readable as":
#   scripts/core/setup_service_subdomains_ssl.sh  — generates a vhost for a new site
#   scripts/core/apply_vhost_change.sh            — replaces an existing vhost
#
# Until 2026-09-18 each carried its own copy of _match_conf_dir_perms, and the copies
# had already diverged on the mode (the generator hardcoded 644; apply took the mode of
# the file it replaced). Two copies of one function drift on the first amendment and the
# divergence is invisible at both call sites, so there is one copy now and it lives here.
#
# WHY A FILE OF ITS OWN, and not scripts/core/script_module.sh: that file is a CLI
# dispatcher. It sets `set -e` and exits 1 when it is given fewer than two arguments, so
# sourcing it would terminate the sourcing script. This file is source-only by
# construction: it sets no shell options, reads no config, writes nothing, and runs
# nothing at source time. It is safe to source from a script that has not loaded jstack's
# config, and safe under `set -e`, `set -u` and `set -o pipefail` alike.

# Put a file written into conf.d under the same ownership as the rest of conf.d, at the
# given mode.
#
#   _match_conf_dir_perms <conf_dir> <file> [mode]
#
# Ownership: a run as root would otherwise leave a root-owned vhost that the stack
# operator's account cannot edit. chown --reference takes conf.d's own owner, so the
# answer is whatever the host already uses rather than a name hardcoded here.
#
# Mode: defaults to 644 — correct for a file that did not exist before. For a file that
# is REPLACING an existing vhost, pass that vhost's mode: nginx/conf.d holds both 644 and
# 600 vhosts on this host (odysseyalive.com.conf is 600), and defaulting to 644 there
# would silently widen it. Callers get that mode from _conf_target_mode below.
#
# On that 600, since this comment used to assert more than it could support: it read the
# mode as one "an operator had deliberately tightened". That was an inference, not a
# record. It was investigated on 2026-09-19 and nobody can say who set it — three
# hypotheses were tested and all three failed, and the mode predates every journal on
# this machine. Preserving it is still the right behaviour, but for a different reason:
# not because the tightening is known to be deliberate, but because its provenance is
# unknown and widening on "we found no reason" would discard the only signal there is.
# See .claude/skills/awareness-ledger/ledger/decisions/
#     DEC-2026-09-19-vhost-0600-left-as-is.md — do not chmod it to satisfy a
# consistency check; the record explains what was checked and what would reopen it.
_match_conf_dir_perms() {
  local nginx_conf_dir="$1" file="$2" mode="${3:-644}"
  chmod "$mode" "$file"
  if [ "$(id -u)" -eq 0 ]; then chown --reference="$nginx_conf_dir" "$file"; fi
}

# The mode a vhost about to be written should end up with: the mode of the file it
# replaces when one exists, else 644.
#
#   _conf_target_mode <file>
#
# Call this BEFORE writing, not after: `cat >` truncates in place and keeps the existing
# mode, so reading it afterwards happens to work today and stops working the moment a
# writer creates the file some other way. Reading it first makes the intent explicit and
# the answer independent of how the write is done.
_conf_target_mode() {
  local file="$1"
  if [ -f "$file" ]; then
    stat -c '%a' "$file"
  else
    echo 644
  fi
}
