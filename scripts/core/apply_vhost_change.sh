#!/bin/bash
# JStack guarded vhost apply — the one safe way to put a generated vhost onto this host.
#
# Usage: apply_vhost_change.sh <domain> <new-conf-file> [--dry-run]
#
# Today a change reaches a live site by writing nginx/conf.d/<domain>.conf and
# reloading. If the result is broken there is nothing that puts the site back, and
# nginx/conf.d/ is gitignored, so `git checkout` recovers nothing. This script is the
# put-it-back half, made mechanical: it backs the live file up and PROVES the backup
# byte-identical before it writes, and it restores that backup on any gate it fails.
#
# Sequence, and the order is the point:
#   1. Precondition — the domain has a live vhost; the new file exists and is non-empty.
#   2. Baseline     — what does the domain answer RIGHT NOW? A site already down before
#                     the change is not reported as broken by the change, and is not
#                     silently "restored" to a state that was already broken.
#   3. Back up      — copy the live file to nginx/conf.d-backups/<UTC-timestamp>/, verify
#                     it readable and byte-identical. No backup, no change.
#   4. Apply        — write the new file, preserving the live file's mode and conf.d's
#                     ownership (_match_conf_dir_perms, in scripts/core/nginx_conf_perms.sh,
#                     shared with the site generator).
#   5. Syntax gate  — `nginx -t` in the container. Fails -> restore, re-test, exit non-zero.
#                     NOTHING is reloaded on a failed syntax gate.
#   6. Reload       — only after the syntax gate passes.
#   7. Liveness gate— re-request the domain. Answered before and not now, or materially
#                     worse -> restore, reload again, re-verify, exit non-zero.
#   8. Conformance  — check_vhost_hardening.sh and check_nginx_ban_guard.sh. A failure here
#                     does NOT roll back: the change may close one gap while another stays
#                     open. Reported as a non-fatal warning with its exit code.
#   9. Report       — what was backed up where, what was applied, every gate's exit code,
#                     and whether a rollback fired.
#
# --dry-run does steps 1, 2 and 3, diffs the new file against the live one, and stops.
# No write, no reload.
#
# ONE DOMAIN PER INVOCATION. A fleet rollout is a loop over this script in its caller,
# never a loop inside it: a bad change that takes down all seven sites in one run is the
# failure mode this design exists to prevent. Running it per domain means the first
# failure rolls itself back and stops the operator before domain two.
#
# Applying a file identical to the live one is a no-op — reported, not skipped silently.
#
# EXIT CODES
#   0  applied and every fatal gate passed (or --dry-run completed, or no-op)
#   1  usage / precondition refusal — nothing was read, written or reloaded
#   2  backup failed or could not be verified — the live file was NOT touched
#   3  syntax gate failed — rolled back, nothing reloaded
#   4  reload failed — rolled back
#   5  liveness gate failed — rolled back and reloaded
#   9  RESTORE FAILED — the host is between states and needs a human. Read the output.
#
# TEST SEAM
#   Three operations need the live host: `nginx -t`, `nginx -s reload`, and the HTTPS
#   request. They are the functions nginx_config_test / nginx_reload / probe_domain, and
#   setting APPLY_VHOST_HOOKS=<file> sources that file AFTER they are defined, so a
#   fixture can override them. CONF_DIR, BACKUP_ROOT, COMPOSE_FILE and CHECK_DIR are
#   likewise overridable. That seam exists so the rollback path can be EXERCISED against a
#   fixture conf dir instead of asserted — a restore that is never run is a restore that
#   does not work.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF_DIR="${CONF_DIR:-$REPO_ROOT/nginx/conf.d}"
BACKUP_ROOT="${BACKUP_ROOT:-$REPO_ROOT/nginx/conf.d-backups}"
COMPOSE_FILE="${COMPOSE_FILE:-$REPO_ROOT/docker-compose.yml}"
CHECK_DIR="${CHECK_DIR:-$REPO_ROOT/scripts/core}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-15}"
PROBE_ATTEMPTS="${PROBE_ATTEMPTS:-3}"
PROBE_INTERVAL="${PROBE_INTERVAL:-2}"

# _match_conf_dir_perms. Shared with setup_service_subdomains_ssl.sh, which writes into
# the same directory and needs the same answer about ownership and mode. It was a second
# copy of that function here until 2026-09-18, kept while a fence stopped this script
# sourcing a file another agent was editing; the fence is gone and two copies of one
# function is the drift class this script exists to prevent one level up. Source-only:
# it sets no shell options and runs nothing, so it cannot disturb `set -euo pipefail`.
# shellcheck source=scripts/core/nginx_conf_perms.sh
. "$REPO_ROOT/scripts/core/nginx_conf_perms.sh"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ---------------------------------------------------------------------------
# The three host operations. Overridable via APPLY_VHOST_HOOKS (see TEST SEAM).
# ---------------------------------------------------------------------------

# `docker compose ... exec -T nginx` is the form jstack.sh:144 and
# full_stack_install.sh:187 use; -T because there is no TTY under a script.
nginx_config_test() {
  docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -t 2>&1
}

nginx_reload() {
  docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -s reload 2>&1
}

# Prints an HTTP status code, or 000 when the domain did not answer at all.
# `curl -o /dev/null -w %{http_code}` is the external verification named in
# .claude/workforce/grounding/live-server-rules.md as the only trustworthy one.
probe_domain() {
  local probe_host="$1" code=""
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "$PROBE_TIMEOUT" \
    "https://${probe_host}/" 2>/dev/null || true)"
  [ -n "$code" ] || code="000"
  echo "$code"
}

if [ -n "${APPLY_VHOST_HOOKS:-}" ]; then
  if [ ! -r "$APPLY_VHOST_HOOKS" ]; then
    log "ERROR: APPLY_VHOST_HOOKS=$APPLY_VHOST_HOOKS is not readable."
    exit 1
  fi
  log "Test seam: sourcing host-operation overrides from $APPLY_VHOST_HOOKS"
  # shellcheck disable=SC1090
  . "$APPLY_VHOST_HOOKS"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

# Worse class = larger number. Used to decide "materially worse status".
status_class() {
  case "$1" in
    000|"") echo 4 ;;
    5??)    echo 3 ;;
    4??)    echo 2 ;;
    *)      echo 1 ;;
  esac
}

probe_with_retry() {
  local probe_host="$1" attempt=1 code="000"
  while [ "$attempt" -le "$PROBE_ATTEMPTS" ]; do
    code="$(probe_domain "$probe_host")"
    if [ "$(status_class "$code")" -lt 4 ]; then
      echo "$code"
      return 0
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$PROBE_ATTEMPTS" ]; then sleep "$PROBE_INTERVAL"; fi
  done
  echo "$code"
}

usage() {
  cat >&2 <<'USAGE'
Usage: apply_vhost_change.sh <domain> <new-conf-file> [--dry-run]

  <domain>         a domain with a live vhost at nginx/conf.d/<domain>.conf
  <new-conf-file>  the replacement config, non-empty
  --dry-run        precondition + baseline + backup + diff, then stop
USAGE
}

# The loudest possible failure: the live file is not the old one and not the new one.
# Name exactly which file is where and what the human must do. No cleanup, no retry loop
# hiding it -- an operator reading this must be able to fix the host by hand.
restore_failed() {
  local detail="$1"
  echo ""
  echo "================================================================"
  echo "RESTORE FAILED — THIS HOST IS BETWEEN STATES AND NEEDS A HUMAN."
  echo "================================================================"
  echo "  Reason:        $detail"
  echo "  Live file:     $LIVE_FILE"
  echo "  Its sha256:    $(sha256_of "$LIVE_FILE" 2>/dev/null || echo 'UNREADABLE/MISSING')"
  echo "  Good backup:   $BACKUP_FILE"
  echo "  Its sha256:    ${BACKUP_SUM:-unknown}"
  echo "  Attempted new: $NEW_FILE"
  echo ""
  echo "  DO THIS, in order:"
  echo "    1. cp -f '$BACKUP_FILE' '$LIVE_FILE'"
  echo "    2. sha256sum '$BACKUP_FILE' '$LIVE_FILE'   # the two must match"
  echo "    3. chmod ${LIVE_MODE:-644} '$LIVE_FILE'"
  echo "    4. docker compose -f '$COMPOSE_FILE' exec -T nginx nginx -t"
  echo "    5. only if step 4 says 'syntax is ok':"
  echo "       docker compose -f '$COMPOSE_FILE' exec -T nginx nginx -s reload"
  echo "    6. curl -sS -o /dev/null -w '%{http_code}\\n' https://$DOMAIN/"
  echo "================================================================"
  exit 9
}

ROLLBACK_FIRED="no"

restore_backup() {
  local reason="$1"
  log "ROLLBACK: $reason"
  cp -f "$BACKUP_FILE" "$LIVE_FILE" || restore_failed "cp of backup over live file failed"
  _match_conf_dir_perms "$CONF_DIR" "$LIVE_FILE" "$LIVE_MODE" \
    || restore_failed "restored content but could not reset mode/ownership"
  local live_sum
  live_sum="$(sha256_of "$LIVE_FILE")" || restore_failed "restored file is unreadable"
  if [ "$live_sum" != "$BACKUP_SUM" ]; then
    restore_failed "restored file does not match the backup ($live_sum != $BACKUP_SUM)"
  fi
  ROLLBACK_FIRED="yes"
  log "ROLLBACK: $LIVE_FILE restored from $BACKUP_FILE (sha256 $live_sum) — byte-identical"
}

# ---------------------------------------------------------------------------
# 1. Precondition
# ---------------------------------------------------------------------------

DRY_RUN="no"
DOMAIN=""
NEW_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN="yes" ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log "ERROR: unknown option '$1'."
      usage
      exit 1
      ;;
    *)
      if [ -z "$DOMAIN" ]; then
        DOMAIN="$1"
      elif [ -z "$NEW_FILE" ]; then
        NEW_FILE="$1"
      else
        log "ERROR: too many arguments ('$1'). One domain per invocation."
        usage
        exit 1
      fi
      ;;
  esac
  shift
done

if [ -z "$DOMAIN" ] || [ -z "$NEW_FILE" ]; then
  log "ERROR: a domain and a new conf file are both required."
  usage
  exit 1
fi

case "$DOMAIN" in
  */*|*..*|"")
    log "ERROR: '$DOMAIN' is not a bare domain; it must not contain '/' or '..'."
    exit 1
    ;;
esac

LIVE_FILE="$CONF_DIR/$DOMAIN.conf"

if [ ! -d "$CONF_DIR" ]; then
  log "ERROR: no nginx conf dir at $CONF_DIR — refusing."
  exit 1
fi
if [ ! -f "$LIVE_FILE" ]; then
  log "ERROR: $DOMAIN has no live vhost at $LIVE_FILE — refusing."
  log "       This script REPLACES an existing vhost. Creating a new site is"
  log "       setup_service_subdomains_ssl.sh's job, not this one."
  exit 1
fi
if [ ! -r "$LIVE_FILE" ]; then
  log "ERROR: live vhost $LIVE_FILE is not readable — refusing."
  exit 1
fi
if [ ! -f "$NEW_FILE" ]; then
  log "ERROR: new conf file '$NEW_FILE' does not exist or is not a regular file — refusing."
  exit 1
fi
if [ ! -s "$NEW_FILE" ]; then
  log "ERROR: new conf file '$NEW_FILE' is empty — refusing."
  exit 1
fi
if [ ! -r "$NEW_FILE" ]; then
  log "ERROR: new conf file '$NEW_FILE' is not readable — refusing."
  exit 1
fi
if [ "$(readlink -f "$NEW_FILE")" = "$(readlink -f "$LIVE_FILE")" ]; then
  log "ERROR: the new conf file IS the live file ($LIVE_FILE) — nothing to apply."
  exit 1
fi

LIVE_MODE="$(stat -c '%a' "$LIVE_FILE")"
LIVE_SUM_BEFORE="$(sha256_of "$LIVE_FILE")"
NEW_SUM="$(sha256_of "$NEW_FILE")"

log "Domain:      $DOMAIN"
log "Live vhost:  $LIVE_FILE (mode $LIVE_MODE, sha256 $LIVE_SUM_BEFORE)"
log "New config:  $NEW_FILE (sha256 $NEW_SUM)"
if [ "$DRY_RUN" = "yes" ]; then log "Mode:        DRY RUN — no write, no reload"; fi

# ---------------------------------------------------------------------------
# 2. Baseline
# ---------------------------------------------------------------------------

log "Baseline: requesting https://$DOMAIN/ ..."
BASELINE_CODE="$(probe_with_retry "$DOMAIN")"
BASELINE_CLASS="$(status_class "$BASELINE_CODE")"

if [ "$BASELINE_CLASS" -ge 4 ]; then
  log "Baseline: DOWN — https://$DOMAIN/ did not answer (status $BASELINE_CODE)."
  log "          The site was already down BEFORE this change. The liveness gate is"
  log "          therefore informational: a rollback cannot restore a working state"
  log "          that did not exist, and this run will not claim it did."
else
  log "Baseline: UP — https://$DOMAIN/ answered $BASELINE_CODE."
fi

# ---------------------------------------------------------------------------
# 3. Back up — and verify before anything is written
# ---------------------------------------------------------------------------
#
# nginx/conf.d-backups/ already held 20260915/ containing files under their original
# basenames, so the convention here is a timestamped directory of original basenames.
# This uses the full UTC timestamp rather than the date alone, so two applies on one day
# cannot overwrite each other's only copy of the previous working config.

BACKUP_STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
BACKUP_DIR="$BACKUP_ROOT/$BACKUP_STAMP"
# Two applies inside the same second would otherwise share a directory and the second
# would overwrite the first's backup -- which, for a gitignored file, is its only copy.
BACKUP_SUFFIX=1
while [ -e "$BACKUP_DIR/$DOMAIN.conf" ]; do
  BACKUP_DIR="$BACKUP_ROOT/$BACKUP_STAMP-$BACKUP_SUFFIX"
  BACKUP_SUFFIX=$((BACKUP_SUFFIX + 1))
done
BACKUP_FILE="$BACKUP_DIR/$DOMAIN.conf"
BACKUP_SUM=""

if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
  log "ERROR: cannot create backup directory $BACKUP_DIR — refusing to apply."
  log "       No backup, no change. $LIVE_FILE is untouched."
  exit 2
fi
if ! cp -p "$LIVE_FILE" "$BACKUP_FILE" 2>/dev/null; then
  log "ERROR: cannot write backup $BACKUP_FILE — refusing to apply."
  log "       No backup, no change. $LIVE_FILE is untouched."
  exit 2
fi
if [ ! -r "$BACKUP_FILE" ]; then
  log "ERROR: backup $BACKUP_FILE is not readable — refusing to apply."
  log "       No backup, no change. $LIVE_FILE is untouched."
  exit 2
fi
if ! cmp -s "$LIVE_FILE" "$BACKUP_FILE"; then
  log "ERROR: backup $BACKUP_FILE is NOT byte-identical to $LIVE_FILE — refusing to apply."
  log "       No backup, no change. $LIVE_FILE is untouched."
  exit 2
fi
BACKUP_SUM="$(sha256_of "$BACKUP_FILE")"
if [ "$BACKUP_SUM" != "$LIVE_SUM_BEFORE" ]; then
  log "ERROR: backup checksum $BACKUP_SUM != live $LIVE_SUM_BEFORE — refusing to apply."
  log "       No backup, no change. $LIVE_FILE is untouched."
  exit 2
fi
log "Backup:   $BACKUP_FILE (sha256 $BACKUP_SUM) — verified readable and byte-identical."

# ---------------------------------------------------------------------------
# --dry-run stops here, after the diff.
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = "yes" ]; then
  echo ""
  if [ "$NEW_SUM" = "$LIVE_SUM_BEFORE" ]; then
    log "DIFF: none — the new file is byte-identical to the live one. Applying it"
    log "      would be a no-op."
  else
    log "DIFF: $LIVE_FILE (live, '-') vs $NEW_FILE (new, '+')"
    echo ""
    diff -u "$LIVE_FILE" "$NEW_FILE" || true
    echo ""
  fi
  echo ""
  echo "=== apply_vhost_change.sh — DRY RUN, $DOMAIN ==="
  echo "  Baseline status:   $BASELINE_CODE"
  echo "  Backed up to:      $BACKUP_FILE (sha256 $BACKUP_SUM)"
  echo "  Live file:         UNCHANGED ($LIVE_FILE, sha256 $LIVE_SUM_BEFORE)"
  echo "  Applied:           nothing"
  echo "  Reloaded:          nothing"
  echo "  Rollback fired:    no"
  echo "==============================================="
  exit 0
fi

# ---------------------------------------------------------------------------
# Idempotence: an identical file is a no-op that still reports.
# ---------------------------------------------------------------------------

if [ "$NEW_SUM" = "$LIVE_SUM_BEFORE" ]; then
  log "NO-OP: the new file is byte-identical to the live one. Nothing written,"
  log "       nothing reloaded. Re-running this command is safe."
  HARDENING_RC=0
  BANGUARD_RC=0
  if [ -f "$CHECK_DIR/check_vhost_hardening.sh" ]; then
    bash "$CHECK_DIR/check_vhost_hardening.sh" "$CONF_DIR" || HARDENING_RC=$?
  else
    HARDENING_RC="skipped"
  fi
  if [ -f "$CHECK_DIR/check_nginx_ban_guard.sh" ]; then
    bash "$CHECK_DIR/check_nginx_ban_guard.sh" "$CONF_DIR" || BANGUARD_RC=$?
  else
    BANGUARD_RC="skipped"
  fi
  echo ""
  echo "=== apply_vhost_change.sh — NO-OP, $DOMAIN ==="
  echo "  Baseline status:   $BASELINE_CODE"
  echo "  Backed up to:      $BACKUP_FILE (sha256 $BACKUP_SUM)"
  echo "  Live file:         UNCHANGED ($LIVE_FILE, sha256 $LIVE_SUM_BEFORE)"
  echo "  Syntax gate:       not run (nothing changed)"
  echo "  Reload:            not run (nothing changed)"
  echo "  Liveness gate:     not run (nothing changed)"
  echo "  Hardening check:   exit $HARDENING_RC (non-fatal)"
  echo "  Ban-guard check:   exit $BANGUARD_RC (non-fatal)"
  echo "  Rollback fired:    no"
  echo "=============================================="
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Apply
# ---------------------------------------------------------------------------
#
# Written to a temp file in the SAME directory and moved into place, so nginx never
# sees a half-written vhost if this script is killed mid-copy.

TMP_FILE="$LIVE_FILE.apply-tmp.$$"
cleanup_tmp() { rm -f "$TMP_FILE" 2>/dev/null || true; }
trap cleanup_tmp EXIT

if ! cp "$NEW_FILE" "$TMP_FILE"; then
  log "ERROR: could not stage the new config at $TMP_FILE — nothing applied."
  log "       $LIVE_FILE is untouched (sha256 $LIVE_SUM_BEFORE)."
  exit 2
fi
_match_conf_dir_perms "$CONF_DIR" "$TMP_FILE" "$LIVE_MODE"
if ! mv -f "$TMP_FILE" "$LIVE_FILE"; then
  log "ERROR: could not move $TMP_FILE onto $LIVE_FILE."
  restore_backup "staging file could not be moved into place"
  exit 2
fi
log "Applied:  $NEW_FILE -> $LIVE_FILE (mode $LIVE_MODE, sha256 $NEW_SUM)"

# ---------------------------------------------------------------------------
# 5. Syntax gate — before any reload. A failed nginx -t reloads NOTHING.
# ---------------------------------------------------------------------------

SYNTAX_RC=0
SYNTAX_OUT="$(nginx_config_test)" || SYNTAX_RC=$?
echo "$SYNTAX_OUT" | sed 's/^/    nginx -t: /'

if [ "$SYNTAX_RC" -ne 0 ]; then
  log "GATE FAILED: nginx -t exited $SYNTAX_RC. Nothing has been reloaded; the running"
  log "             nginx is still serving the OLD config from memory."
  restore_backup "syntax gate failed (nginx -t exit $SYNTAX_RC)"
  RETEST_RC=0
  RETEST_OUT="$(nginx_config_test)" || RETEST_RC=$?
  echo "$RETEST_OUT" | sed 's/^/    nginx -t (after restore): /'
  echo ""
  echo "=== apply_vhost_change.sh — ROLLED BACK, $DOMAIN ==="
  echo "  Baseline status:   $BASELINE_CODE"
  echo "  Backed up to:      $BACKUP_FILE (sha256 $BACKUP_SUM)"
  echo "  Applied:           $NEW_FILE (sha256 $NEW_SUM) — then reverted"
  echo "  Syntax gate:       exit $SYNTAX_RC  FAILED"
  echo "  Reload:            not run"
  echo "  Liveness gate:     not run"
  echo "  Restored file:     $LIVE_FILE (sha256 $(sha256_of "$LIVE_FILE"))"
  echo "  Re-test after restore: exit $RETEST_RC"
  echo "  Rollback fired:    $ROLLBACK_FIRED"
  echo "===================================================="
  if [ "$RETEST_RC" -ne 0 ]; then
    log "WARNING: nginx -t still fails AFTER the restore. The restored vhost is the one"
    log "         that was live, so the fault is elsewhere in conf.d — investigate before"
    log "         anyone reloads."
  fi
  exit 3
fi
log "Syntax gate: nginx -t exit 0."

# ---------------------------------------------------------------------------
# 6. Reload
# ---------------------------------------------------------------------------

RELOAD_RC=0
RELOAD_OUT="$(nginx_reload)" || RELOAD_RC=$?
if [ -n "$RELOAD_OUT" ]; then echo "$RELOAD_OUT" | sed 's/^/    nginx -s reload: /'; fi

if [ "$RELOAD_RC" -ne 0 ]; then
  log "GATE FAILED: nginx -s reload exited $RELOAD_RC."
  restore_backup "reload failed (exit $RELOAD_RC)"
  RERELOAD_RC=0
  nginx_reload >/dev/null 2>&1 || RERELOAD_RC=$?
  echo ""
  echo "=== apply_vhost_change.sh — ROLLED BACK, $DOMAIN ==="
  echo "  Baseline status:   $BASELINE_CODE"
  echo "  Backed up to:      $BACKUP_FILE (sha256 $BACKUP_SUM)"
  echo "  Applied:           $NEW_FILE (sha256 $NEW_SUM) — then reverted"
  echo "  Syntax gate:       exit 0"
  echo "  Reload:            exit $RELOAD_RC  FAILED"
  echo "  Reload after restore: exit $RERELOAD_RC"
  echo "  Restored file:     $LIVE_FILE (sha256 $(sha256_of "$LIVE_FILE"))"
  echo "  Rollback fired:    $ROLLBACK_FIRED"
  echo "===================================================="
  exit 4
fi
log "Reload:   nginx -s reload exit 0."

# ---------------------------------------------------------------------------
# 7. Liveness gate
# ---------------------------------------------------------------------------

log "Liveness: re-requesting https://$DOMAIN/ ..."
AFTER_CODE="$(probe_with_retry "$DOMAIN")"
AFTER_CLASS="$(status_class "$AFTER_CODE")"
log "Liveness: before=$BASELINE_CODE after=$AFTER_CODE"

LIVENESS_VERDICT="pass"
if [ "$BASELINE_CLASS" -ge 4 ]; then
  LIVENESS_VERDICT="not-applicable (site was already down at baseline)"
elif [ "$AFTER_CLASS" -gt "$BASELINE_CLASS" ]; then
  LIVENESS_VERDICT="fail"
fi

if [ "$LIVENESS_VERDICT" = "fail" ]; then
  log "GATE FAILED: $DOMAIN answered $BASELINE_CODE before this change and $AFTER_CODE after."
  restore_backup "liveness gate failed (before=$BASELINE_CODE after=$AFTER_CODE)"
  RERELOAD_RC=0
  nginx_reload >/dev/null 2>&1 || RERELOAD_RC=$?
  VERIFY_CODE="$(probe_with_retry "$DOMAIN")"
  echo ""
  echo "=== apply_vhost_change.sh — ROLLED BACK, $DOMAIN ==="
  echo "  Baseline status:   $BASELINE_CODE"
  echo "  Status after apply: $AFTER_CODE"
  echo "  Backed up to:      $BACKUP_FILE (sha256 $BACKUP_SUM)"
  echo "  Applied:           $NEW_FILE (sha256 $NEW_SUM) — then reverted"
  echo "  Syntax gate:       exit 0"
  echo "  Reload:            exit 0"
  echo "  Liveness gate:     FAILED ($BASELINE_CODE -> $AFTER_CODE)"
  echo "  Restored file:     $LIVE_FILE (sha256 $(sha256_of "$LIVE_FILE"))"
  echo "  Reload after restore: exit $RERELOAD_RC"
  echo "  Status after restore: $VERIFY_CODE"
  echo "  Rollback fired:    $ROLLBACK_FIRED"
  echo "===================================================="
  if [ "$VERIFY_CODE" != "$BASELINE_CODE" ]; then
    log "WARNING: after the restore $DOMAIN answers $VERIFY_CODE, not the baseline"
    log "         $BASELINE_CODE. The config is back to byte-identical, so the"
    log "         difference is not this file — investigate the upstream container."
  fi
  exit 5
fi

# ---------------------------------------------------------------------------
# 8. Conformance gates — reported, never a rollback reason.
# ---------------------------------------------------------------------------

HARDENING_RC=0
BANGUARD_RC=0
if [ -f "$CHECK_DIR/check_vhost_hardening.sh" ]; then
  bash "$CHECK_DIR/check_vhost_hardening.sh" "$CONF_DIR" || HARDENING_RC=$?
else
  log "WARNING: $CHECK_DIR/check_vhost_hardening.sh not found — conformance not checked."
  HARDENING_RC="skipped"
fi
if [ -f "$CHECK_DIR/check_nginx_ban_guard.sh" ]; then
  bash "$CHECK_DIR/check_nginx_ban_guard.sh" "$CONF_DIR" || BANGUARD_RC=$?
else
  log "WARNING: $CHECK_DIR/check_nginx_ban_guard.sh not found — ban guard not checked."
  BANGUARD_RC="skipped"
fi
if [ "$HARDENING_RC" != "0" ] || [ "$BANGUARD_RC" != "0" ]; then
  log "WARNING: a conformance check did not pass (hardening=$HARDENING_RC"
  log "         ban-guard=$BANGUARD_RC). This is NOT a rollback: the change may close"
  log "         one gap while another stays open. The change stands; fix the rest in the"
  log "         generator, not by hand in conf.d."
fi

# ---------------------------------------------------------------------------
# 9. Report
# ---------------------------------------------------------------------------

echo ""
echo "=== apply_vhost_change.sh — APPLIED, $DOMAIN ==="
echo "  Backed up to:      $BACKUP_FILE (sha256 $BACKUP_SUM)"
echo "  Previous live:     sha256 $LIVE_SUM_BEFORE, mode $LIVE_MODE"
echo "  Applied:           $NEW_FILE -> $LIVE_FILE (sha256 $NEW_SUM)"
echo "  Syntax gate:       exit 0"
echo "  Reload:            exit 0"
echo "  Liveness gate:     $LIVENESS_VERDICT (before=$BASELINE_CODE after=$AFTER_CODE)"
echo "  Hardening check:   exit $HARDENING_RC (non-fatal)"
echo "  Ban-guard check:   exit $BANGUARD_RC (non-fatal)"
echo "  Rollback fired:    $ROLLBACK_FIRED"
echo "  Undo this by hand: cp -f '$BACKUP_FILE' '$LIVE_FILE' && \\"
echo "                     docker compose -f '$COMPOSE_FILE' exec -T nginx nginx -t && \\"
echo "                     docker compose -f '$COMPOSE_FILE' exec -T nginx nginx -s reload"
echo "================================================"
exit 0
