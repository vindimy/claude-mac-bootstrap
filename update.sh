#!/bin/bash
# Update Homebrew and every app in this machine's saved selection.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fetch the latest automation before running it (the repo is distributed by
# git clone). Runs before the libs are sourced so the fresh code is what
# executes. Never fatal: offline machines and diverged dev checkouts just
# run what they have.
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO_ROOT" pull --ff-only --quiet 2>/dev/null ||
    echo "warning: could not fast-forward $REPO_ROOT; running the current checkout" >&2
fi

# shellcheck disable=SC1091
. "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/drivers.sh"

usage() {
  cat <<'EOF'
Usage: update.sh [--dry-run] [--help]

Pulls the latest automation, updates Homebrew, then updates each app in this
machine's saved selection (~/.mac-bootstrap/apps.conf). Only managed apps are
touched — other brew packages are left alone. Run ./run.sh to change the
selection.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    # Exported (not just set) so shellcheck (SC2034) sees it used externally
    # by lib/common.sh; behavior-neutral, common.sh reads it via env either way.
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
