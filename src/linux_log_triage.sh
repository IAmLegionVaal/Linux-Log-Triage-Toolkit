#!/usr/bin/env bash
set -u

HOURS=24
KEYWORD=""
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --keyword) KEYWORD="${2:-}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--hours N] [--keyword REGEX] [--output DIR]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }
command -v journalctl >/dev/null 2>&1 || { echo "journalctl is required." >&2; exit 1; }
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./linux-log-triage-$STAMP}"
mkdir -p "$OUTPUT_DIR"
RAW="$OUTPUT_DIR/journal-raw.log"
REPORT="$OUTPUT_DIR/log-triage.txt"
CSV="$OUTPUT_DIR/top-messages.csv"
JSON="$OUTPUT_DIR/log-summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"; : > "$ERRORS"

SINCE="$HOURS hours ago"
journalctl --since "$SINCE" --no-pager -o short-iso > "$RAW" 2>> "$ERRORS" || true
FILTERED="$RAW"
if [[ -n "$KEYWORD" ]]; then
  grep -Ei "$KEYWORD" "$RAW" > "$OUTPUT_DIR/journal-filtered.log" || true
  FILTERED="$OUTPUT_DIR/journal-filtered.log"
fi

section() { local title="$1"; shift; { printf '\n===== %s =====\n' "$title"; "$@"; } >> "$REPORT" 2>> "$ERRORS" || true; }
section "Collection metadata" bash -c "date -Is; hostname -f 2>/dev/null || hostname; echo 'Window: $HOURS hours'; echo 'Keyword: ${KEYWORD:-none}'"
section "Critical and error events" journalctl --since "$SINCE" -p 0..3 --no-pager -o short-iso
section "Current boot warnings" journalctl -b -p 0..4 --no-pager -o short-iso
section "Kernel warnings" journalctl -k --since "$SINCE" -p 0..4 --no-pager -o short-iso
section "Authentication and sudo" bash -c "grep -Ei 'failed password|authentication failure|invalid user|sudo:|session opened|session closed' '$FILTERED' | tail -n 500 || true"
section "Storage and filesystem indicators" bash -c "grep -Ei 'I/O error|buffer I/O|ext4|xfs|btrfs|nvme|ata[0-9]|read-only file system|filesystem error' '$FILTERED' | tail -n 500 || true"
section "Memory pressure" bash -c "grep -Ei 'out of memory|oom-killer|killed process|memory cgroup' '$FILTERED' | tail -n 500 || true"
section "Service failures" bash -c "grep -Ei 'failed|failure|start request repeated|dependency failed|main process exited' '$FILTERED' | tail -n 500 || true"

{
  echo 'count,message'
  sed -E 's/^[0-9-]+T[^ ]+ [^ ]+ [^:]+: //' "$FILTERED" | sed '/^[[:space:]]*$/d' | sort | uniq -c | sort -nr | head -n 50 | awk '{count=$1; $1=""; sub(/^ /,""); gsub(/"/,"\"\""); printf "%s,\"%s\"\n", count, $0}'
} > "$CSV"

CRITICAL_COUNT="$(journalctl --since "$SINCE" -p 0..3 --no-pager 2>/dev/null | sed '/^-- No entries --$/d;/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
AUTH_FAILURES="$(grep -Eic 'failed password|authentication failure|invalid user' "$FILTERED" 2>/dev/null || true)"
OOM_COUNT="$(grep -Eic 'out of memory|oom-killer|killed process' "$FILTERED" 2>/dev/null || true)"

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "window_hours": $HOURS,
  "critical_error_entries": ${CRITICAL_COUNT:-0},
  "authentication_failures": ${AUTH_FAILURES:-0},
  "memory_pressure_events": ${OOM_COUNT:-0},
  "keyword_filter": "${KEYWORD//"/\"}"
}
EOF

printf '\nLog triage completed. Output: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
