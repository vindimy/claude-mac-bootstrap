#!/bin/bash
# Entry point: bootstrap Homebrew + dotfiles, choose managed apps, reconcile.
# Interactive by default; see --help for non-interactive use.
#
# Also runs standalone: curl this one file onto a fresh Mac and execute it —
# it shallow-clones the repo into ~/.mac-bootstrap/repo and re-execs from there.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ ! -f "$REPO_ROOT/lib/common.sh" ]; then
  # Standalone mode: this is a lone curl-ed copy (or `curl | bash`), not a
  # checkout. Fetch the real repo, then hand over to its run.sh.
  BOOTSTRAP_HOME="${MAC_BOOTSTRAP_HOME:-$HOME/.mac-bootstrap}"
  REPO_URL="${MAC_BOOTSTRAP_REPO:-https://github.com/vindimy/claude-mac-bootstrap.git}"
  REPO_DIR="$BOOTSTRAP_HOME/repo"
  # A fresh macOS has a git stub that pops a GUI dialog; detect the Command
  # Line Tools directly so the flow stays scriptable.
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "git needs the Xcode Command Line Tools — starting their installer now." >&2
    echo "Re-run this script once that installation finishes." >&2
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
  fi
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only
  else
    mkdir -p "$BOOTSTRAP_HOME"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  fi
  # Under `curl | bash` stdin is the pipe; reattach the terminal (when one
  # can actually be opened) so the interactive checklist can read answers.
  if [ ! -t 0 ] && { : </dev/tty; } 2>/dev/null; then
    exec "$REPO_DIR/run.sh" ${1+"$@"} </dev/tty
  fi
  exec "$REPO_DIR/run.sh" ${1+"$@"}
fi

# shellcheck disable=SC1091
. "$REPO_ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/drivers.sh"
# shellcheck disable=SC1091
. "$REPO_ROOT/lib/ui.sh"

usage() {
  cat <<'EOF'
Usage: run.sh [--non-interactive] [--apps id1,id2,...] [--dry-run] [--help]

Installs Homebrew (if missing) and the repo dotfiles, then reconciles this
machine's managed apps: newly selected apps are installed, still-selected apps
are updated, deselected apps are uninstalled. The selection is saved to
~/.mac-bootstrap/apps.conf.

  --non-interactive  no prompts; requires a saved selection or --apps
  --apps LIST        comma-separated app ids as the exact new selection
                     (--apps none selects nothing, uninstalling everything
                     previously managed)
  --dry-run          print every action instead of executing
  --help             this text
EOF
}

NON_INTERACTIVE=0
APPS_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=1 ;;
    --apps)
      if [ $# -lt 2 ]; then
        err "--apps requires a value"
        usage
        exit 2
      fi
      shift
      APPS_ARG="${1:-}"
      ;;
    --apps=*) APPS_ARG="${1#--apps=}" ;;
    --dry-run) DRY_RUN=1 ;;
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

if [ "$DRY_RUN" = 1 ]; then
  log "[dry-run] ./install.sh (dotfile symlinks)"
else
  "$REPO_ROOT/install.sh"
fi

discover_apps

HAVE_CONFIG=0
if load_config; then HAVE_CONFIG=1; fi

if [ -n "$APPS_ARG" ]; then
  if [ "$APPS_ARG" = none ]; then
    NEW_SELECTED=""
  else
    NEW_SELECTED="$(printf '%s' "$APPS_ARG" | tr ',' ' ')"
    validate_selection "$NEW_SELECTED"
  fi
elif [ "$NON_INTERACTIVE" = 1 ]; then
  if [ "$HAVE_CONFIG" = 0 ]; then
    err "no saved selection at $(config_file) — run interactively once or pass --apps"
    exit 1
  fi
  NEW_SELECTED="$SELECTED"
else
  select_apps
fi

INSTALLED=""
UPDATED=""
REMOVED=""
FAILED=""
REMOVE_FAILED=""

# shellcheck disable=SC2086
for id in $NEW_SELECTED; do
  if in_list "$id" "$SELECTED"; then
    log "== updating $(app_name_for "$id")"
    if "$(app_fn "$id" update)"; then
      UPDATED="$UPDATED $id"
    else
      FAILED="$FAILED $id"
    fi
  else
    log "== installing $(app_name_for "$id")"
    if "$(app_fn "$id" install)" && "$(app_fn "$id" update)"; then
      INSTALLED="$INSTALLED $id"
    else
      FAILED="$FAILED $id"
    fi
  fi
done

# shellcheck disable=SC2086
for id in $SELECTED; do
  if in_list "$id" "$NEW_SELECTED"; then continue; fi
  mode=keep
  if [ "$NON_INTERACTIVE" = 0 ]; then
    mode="$(prompt_uninstall_mode "$(app_name_for "$id")")"
  fi
  log "== removing $(app_name_for "$id") (settings: $mode)"
  if "$(app_fn "$id" uninstall)" "$mode"; then
    REMOVED="$REMOVED $id"
  else
    FAILED="$FAILED $id"
    REMOVE_FAILED="$REMOVE_FAILED $id"
  fi
done

# Failed removals stay installed, so keep them in the saved selection —
# otherwise a failed uninstall would be forgotten and never retried.
if [ "$DRY_RUN" = 1 ]; then
  log "[dry-run] save selection [$NEW_SELECTED$REMOVE_FAILED] to $(config_file)"
else
  SELECTED="$NEW_SELECTED$REMOVE_FAILED"
  save_config
fi

log ""
log "Summary:"
if [ -n "$INSTALLED" ]; then log "  installed:$INSTALLED"; fi
if [ -n "$UPDATED" ]; then log "  updated:$UPDATED"; fi
if [ -n "$REMOVED" ]; then log "  removed:$REMOVED"; fi
if [ -z "$INSTALLED$UPDATED$REMOVED$FAILED" ]; then log "  nothing to do"; fi
# shellcheck disable=SC2086
for id in $INSTALLED; do
  note="$(app_note_for "$id")"
  if [ -n "$note" ]; then log "  NOTE [$(app_name_for "$id")]: $note"; fi
done
if [ -n "$FAILED" ]; then
  err "failed:$FAILED (see messages above)"
  exit 1
fi
