#!/bin/bash
# Update Homebrew and every app in this machine's saved selection.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/drivers.sh"

usage() {
  cat <<'EOF'
Usage: update.sh [--dry-run] [--help]

Updates Homebrew, then updates each app in this machine's saved selection
(local/<hostname>.conf). Only managed apps are touched — other brew packages
are left alone. Run ./run.sh to change the selection.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) export DRY_RUN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      err "unknown flag: $1"
      usage
      exit 2
      ;;
  esac
  shift
done

ensure_homebrew
discover_apps

if ! load_config; then
  err "no saved selection at $(config_file) — run ./run.sh first"
  exit 1
fi

if [ -z "$SELECTED" ]; then
  log "no apps selected on this machine; nothing to update"
  exit 0
fi

run_cmd brew update

UPDATED=""
FAILED=""
# shellcheck disable=SC2086
for id in $SELECTED; do
  log "== updating $(app_name_for "$id")"
  if "$(app_fn "$id" update)"; then
    UPDATED="$UPDATED $id"
  else
    FAILED="$FAILED $id"
  fi
done

log ""
log "Summary:"
if [ -n "$UPDATED" ]; then log "  updated:$UPDATED"; fi
if [ -n "$FAILED" ]; then
  err "failed:$FAILED (see messages above)"
  exit 1
fi
