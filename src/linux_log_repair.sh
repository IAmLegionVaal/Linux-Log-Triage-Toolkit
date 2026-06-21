#!/usr/bin/env bash
set -u

RESTART_JOURNAL=false
ROTATE=false
VACUUM_DAYS=""
VACUUM_SIZE=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: linux_log_repair.sh [options]

  --restart-journald      Restart systemd-journald.
  --rotate                Request journal and logrotate rotation.
  --vacuum-days DAYS      Remove archived journal data older than DAYS.
  --vacuum-size SIZE      Reduce archived journal data to SIZE, such as 500M.
  --dry-run               Show commands without changing the system.
  --yes                   Skip confirmation prompts.
  --output DIR            Save logs and before/after verification in DIR.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --restart-journald) RESTART_JOURNAL=true; shift ;;
    --rotate) ROTATE=true; shift ;;
    --vacuum-days) VACUUM_DAYS="${2:-}"; shift 2 ;;
    --vacuum-size) VACUUM_SIZE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if ! $RESTART_JOURNAL && ! $ROTATE && [ -z "$VACUUM_DAYS" ] && [ -z "$VACUUM_SIZE" ]; then echo "Choose at least one repair action." >&2; exit 2; fi
if [ -n "$VACUUM_DAYS" ]; then case "$VACUUM_DAYS" in ''|*[!0-9]*) echo "Days must be numeric." >&2; exit 2 ;; esac; fi
if [ -n "$VACUUM_SIZE" ]; then case "$VACUUM_SIZE" in *[!0-9KMGTPkmgpt]*) echo "Invalid journal size." >&2; exit 2 ;; esac; fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${OUTPUT_DIR:-./linux-log-repair-$STAMP}"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/repair.log"
BEFORE="$OUTPUT_DIR/before.txt"
AFTER="$OUTPUT_DIR/after.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() { $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " answer; case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac; }
run_action() {
  local description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then printf 'DRY-RUN:' >> "$LOG"; printf ' %q' "$@" >> "$LOG"; printf '\n' >> "$LOG"; return 0; fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_root() { local description="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" sudo "$@"; fi; }
collect_state() {
  local destination="$1"
  {
    echo "Collected: $(date -Is)"
    journalctl --disk-usage 2>&1 || true
    echo
    systemctl status systemd-journald --no-pager -l 2>&1 || true
    echo
    df -h / /var /var/log 2>/dev/null || true
    echo
    journalctl -p err -n 100 --no-pager 2>&1 || true
  } > "$destination"
}

collect_state "$BEFORE"
confirm "Apply the selected log-service and retention actions?" || { log "Repair cancelled."; exit 10; }

if $RESTART_JOURNAL; then run_root "Restarting systemd-journald" systemctl restart systemd-journald || true; fi
if $ROTATE; then
  run_root "Rotating the system journal" journalctl --rotate || true
  if command -v logrotate >/dev/null 2>&1 && [ -f /etc/logrotate.conf ]; then run_root "Running logrotate" logrotate /etc/logrotate.conf || true; fi
fi
if [ -n "$VACUUM_DAYS" ]; then run_root "Removing archived journal data older than $VACUUM_DAYS days" journalctl --vacuum-time="${VACUUM_DAYS}d" || true; fi
if [ -n "$VACUUM_SIZE" ]; then run_root "Reducing archived journal data to $VACUUM_SIZE" journalctl --vacuum-size="$VACUUM_SIZE" || true; fi

$DRY_RUN || sleep 2
collect_state "$AFTER"
if $RESTART_JOURNAL; then systemctl is-active --quiet systemd-journald || { FAILURES=$((FAILURES + 1)); log "WARNING: journald is not active after repair."; }; fi
if [ "$FAILURES" -gt 0 ]; then exit 20; fi
log "Repair completed successfully. Actions performed: $ACTIONS"
exit 0
