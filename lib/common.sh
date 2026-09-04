#!/bin/bash
# Shared plumbing for run.sh / update.sh: logging, dry-run, per-machine config,
# app discovery. Sourced, never executed. Must work on stock macOS bash 3.2.
# Requires $REPO_ROOT to be set by the sourcing script.

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; }

DRY_RUN="${DRY_RUN:-0}"

# Run a mutating command, or print it under --dry-run.
run_cmd() {
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

# in_list item space-separated-list -> 0 if present
in_list() {
  case " $2 " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# remove_from_list item space-separated-list -> prints list without item
remove_from_list() {
  local out="" x
  # shellcheck disable=SC2086
  for x in $2; do
    if [ "$x" != "$1" ]; then out="$out $x"; fi
  done
  printf '%s\n' "$out"
}

# Bootstrap state lives in the user's home dir, outside the repo — the repo
# holds only automation and can be cloned anywhere (default: ~/.mac-bootstrap/repo).
CONFIG_DIR="${BOOTSTRAP_CONFIG_DIR:-${MAC_BOOTSTRAP_HOME:-$HOME/.mac-bootstrap}}"

config_file() { printf '%s/apps.conf\n' "$CONFIG_DIR"; }

# Pre-2026-09-03 the selection lived in the repo at local/<hostname>.conf;
# adopt such a file into ~/.mac-bootstrap/apps.conf once, then forget it.
migrate_legacy_config() {
  local legacy new
  new="$(config_file)"
  legacy="$REPO_ROOT/local/$(hostname -s).conf"
  if [ ! -f "$new" ] && [ -f "$legacy" ]; then
    mkdir -p "$CONFIG_DIR"
    mv "$legacy" "$new"
    log "moved app selection: $legacy -> $new"
  fi
}

# Sets SELECTED from this machine's config; SELECTED="" and return 1 if absent.
load_config() {
  SELECTED=""
  local cf
  migrate_legacy_config
  cf="$(config_file)"
  if [ ! -f "$cf" ]; then return 1; fi
  # shellcheck source=/dev/null
  . "$cf"
}

# Persists SELECTED to this machine's config.
save_config() {
  local cf
  cf="$(config_file)"
  mkdir -p "$CONFIG_DIR"
  {
    printf '# Managed by run.sh — per-machine app selection.\n'
    printf 'SELECTED="%s"\n' "$SELECTED"
  } >"$cf"
  log "saved selection to $cf"
}

# Install Homebrew if missing and make brew available to this process.
ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then return 0; fi
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"; return 0
  fi
  if [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"; return 0
  fi
  log "Homebrew not found — installing"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] install Homebrew from https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    return 0
  fi
  # Bypasses run_cmd deliberately: run_cmd would still evaluate this command
  # substitution under --dry-run, eagerly curling the install script even
  # though nothing would execute — the dry-run branch above already returned.
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew install finished but brew is not on PATH; aborting"
    exit 1
  fi
}

# Parallel arrays filled by discover_apps (same index = same app).
APP_IDS=()
APP_NAMES=()
APP_NOTES=()

# Source every apps/*.sh, capturing its APP_NAME/APP_NOTE and defining its
# <id>_* functions in the current shell.
discover_apps() {
  local f id
  for f in "$REPO_ROOT"/apps/*.sh; do
    if [ ! -e "$f" ]; then break; fi
    id="$(basename "$f" .sh)"
    APP_NAME=""
    APP_NOTE=""
    # shellcheck source=/dev/null
    . "$f"
    APP_IDS+=("$id")
    APP_NAMES+=("${APP_NAME:-$id}")
    APP_NOTES+=("$APP_NOTE")
  done
  if [ "${#APP_IDS[@]}" -eq 0 ]; then
    err "no app definitions found in $REPO_ROOT/apps"
    exit 1
  fi
}

app_name_for() {
  local i=0
  while [ "$i" -lt "${#APP_IDS[@]}" ]; do
    if [ "${APP_IDS[$i]}" = "$1" ]; then printf '%s\n' "${APP_NAMES[$i]}"; return 0; fi
    i=$((i + 1))
  done
  printf '%s\n' "$1"
}

app_note_for() {
  local i=0
  while [ "$i" -lt "${#APP_IDS[@]}" ]; do
    if [ "${APP_IDS[$i]}" = "$1" ]; then printf '%s\n' "${APP_NOTES[$i]}"; return 0; fi
    i=$((i + 1))
  done
  printf '\n'
}

# app_fn id suffix -> function name (hyphens become underscores)
app_fn() { printf '%s_%s\n' "$(printf '%s' "$1" | tr - _)" "$2"; }

# Exit 2 if any id in $1 is not a discovered app id.
validate_selection() {
  local id known ok
  # shellcheck disable=SC2086
  for id in $1; do
    ok=0
    for known in "${APP_IDS[@]}"; do
      if [ "$id" = "$known" ]; then ok=1; fi
    done
    if [ "$ok" = 0 ]; then
      err "unknown app id: $id (valid: ${APP_IDS[*]})"
      exit 2
    fi
  done
}
