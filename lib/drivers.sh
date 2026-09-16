#!/bin/bash
# Install/update/uninstall drivers shared by apps/*.sh.
# Sourced after lib/common.sh (uses run_cmd/log/err/DRY_RUN).

# ---- Homebrew cask ----------------------------------------------------------

# Homebrew's receipt outlives the app: drag WhatsApp.app to the Trash and
# `brew list --cask whatsapp` still reports it installed, so every later update
# pass skips it and the app never comes back. Brew stages each artifact in the
# Caskroom as a symlink to wherever it installed it, and `brew list --cask`
# prints those paths, so a link that no longer resolves means the artifact was
# removed by hand. Nothing app-specific is hardcoded; casks that stage no
# symlink (pkg installers) are judged by the receipt alone, as before.
#
# cask_state name -> absent (no receipt) | orphaned (receipt, artifact gone)
#                    | present
cask_state() {
  local listing path
  listing="$(brew list --cask "$1" 2>/dev/null)" || {
    printf 'absent\n'
    return 0
  }
  # Fed by a redirect, not a pipe, so `return` leaves the function.
  while IFS= read -r path; do
    if [ -L "$path" ] && [ ! -e "$path" ]; then
      printf 'orphaned\n'
      return 0
    fi
  done <<EOF
$listing
EOF
  printf 'present\n'
}

# True only when the app is really on disk. An orphaned receipt counts as not
# installed, so cask_update routes it back through cask_install.
cask_installed() { [ "$(cask_state "$1")" = present ]; }

# --adopt takes over an app the user already installed manually, but only
# when it is identical to the cask's copy. Self-updating apps usually drift
# from the cask version, so on adopt failure fall back to --force: the bundle
# is replaced by the cask's copy (settings in ~/Library survive) and the
# app's own updater brings it current afterward. Under --dry-run, run_cmd
# returns 0, so only the adopt line is printed.
cask_install() {
  # A surviving receipt makes `brew install` a no-op ("already installed"),
  # which would leave the deleted app deleted; only reinstall re-stages it.
  if [ "$(cask_state "$1")" = orphaned ]; then
    warn "$1: brew still records it as installed but the installed app is gone (deleted by hand?) — reinstalling"
    run_cmd brew reinstall --cask "$1"
    return
  fi
  if ! run_cmd brew install --cask --adopt "$1"; then
    warn "$1: existing app differs from the cask — replacing it with the brew-managed copy (settings preserved)"
    run_cmd brew install --cask --force "$1"
  fi
}

# `brew outdated <name>` exits non-zero when a newer version exists. Casks
# marked auto_updates (Chrome, Claude, ChatGPT, Gemini) are not reported
# outdated here on purpose — those apps update themselves.
cask_update() {
  if ! cask_installed "$1"; then
    cask_install "$1"
    return
  fi
  if ! brew outdated --cask "$1" >/dev/null 2>&1; then
    run_cmd brew upgrade --cask "$1"
  fi
}

# Homebrew uninstalls a cask by copying the app from /Applications back into
# the Caskroom, then deleting the Caskroom. An interrupted uninstall leaves the
# app only in the Caskroom, and every later plain uninstall then fails with
# "It seems there is already an App at '/opt/homebrew/Caskroom/...'".
# --force overwrites that leftover copy and removes every staged version, so
# it is only retried after the user confirms. Non-interactive runs (and
# update.sh, which has no prompt helper) fail as before. Under --dry-run,
# run_cmd returns 0, so only the plain uninstall line is printed.
cask_uninstall() {
  local name="$1" mode="${2:-keep}"
  # Receipt-based, not cask_installed: an orphaned cask has a receipt and a
  # Caskroom dir to clear even though its app is already gone.
  if [ "$(cask_state "$name")" = absent ]; then
    log "$name: not installed via brew, nothing to remove"
    return 0
  fi
  if [ "$mode" = zap ]; then
    run_cmd brew uninstall --cask --zap "$name" && return 0
  else
    run_cmd brew uninstall --cask "$name" && return 0
  fi
  if [ "${NON_INTERACTIVE:-1}" = 1 ] || ! command -v prompt_confirm >/dev/null 2>&1; then
    err "$name: brew uninstall failed; rerun interactively to retry with --force, or run: brew uninstall --cask --force $name"
    return 1
  fi
  warn "$name: brew uninstall failed (usually a leftover copy in the Caskroom from an interrupted uninstall)"
  if ! prompt_confirm "Retry with --force? This overwrites the leftover Caskroom copy and removes all staged versions of $name"; then
    err "$name: removal skipped; it stays selected and will be retried next run"
    return 1
  fi
  if [ "$mode" = zap ]; then
    run_cmd brew uninstall --cask --force --zap "$name"
  else
    run_cmd brew uninstall --cask --force "$name"
  fi
}

# ---- Rosetta 2 ---------------------------------------------------------------

# Some vendors ship Intel-only pkgs (Amnezia VPN's cask is an x64 pkg), whose
# installer refuses outright on Apple silicon without Rosetta 2:
# "This package requires Rosetta 2 to be installed." Call before such
# installs. No-op on Intel Macs and when Rosetta already runs x86_64 code.
# --agree-to-license skips softwareupdate's interactive license prompt; sudo
# may ask for the admin password.
rosetta_installed() {
  [ "$(uname -m)" != arm64 ] || /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null
}

ensure_rosetta() {
  if rosetta_installed; then
    return 0
  fi
  log "$1 ships an Intel-only installer — installing Rosetta 2 first (admin password may be asked)"
  if ! run_cmd sudo softwareupdate --install-rosetta --agree-to-license; then
    err "$1: Rosetta 2 install failed; run 'sudo softwareupdate --install-rosetta' and re-run"
    return 1
  fi
}

# ---- Homebrew formula -------------------------------------------------------

formula_installed() { brew list --formula "$1" >/dev/null 2>&1; }

formula_install() { run_cmd brew install "$1"; }

formula_update() {
  if ! formula_installed "$1"; then
    formula_install "$1"
    return
  fi
  if ! brew outdated --formula "$1" >/dev/null 2>&1; then
    run_cmd brew upgrade --formula "$1"
  fi
}

# Formulas have no --zap; zap mode is the same as keep.
formula_uninstall() {
  if ! formula_installed "$1"; then
    log "$1: not installed via brew, nothing to remove"
    return 0
  fi
  run_cmd brew uninstall --formula "$1"
}

# ---- Direct dmg (vendor download) ------------------------------------------

dmg_installed() { [ -d "/Applications/$1.app" ]; }

# dmg_install url bundle-name: download, mount, copy the .app, unmount.
dmg_install() {
  local url="$1" app="$2" tmp dmg vol
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] download $url and install /Applications/$app.app"
    return 0
  fi
  tmp="$(mktemp -d)"
  dmg="$tmp/app.dmg"
  if ! curl -fL --retry 2 -o "$dmg" "$url"; then
    err "$app: download failed: $url — install manually from the vendor site"
    rm -rf "$tmp"
    return 1
  fi
  vol="$(hdiutil attach -nobrowse -readonly "$dmg" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)"
  if [ -z "$vol" ] || [ ! -d "$vol/$app.app" ]; then
    err "$app: $app.app not found in dmg from $url"
    if [ -n "$vol" ]; then hdiutil detach "$vol" -quiet || true; fi
    rm -rf "$tmp"
    return 1
  fi
  # ditto merges into an existing bundle; remove any pre-existing copy first
  # so stale files from an older version cannot linger inside the new one.
  if [ -d "/Applications/$app.app" ]; then
    rm -rf "/Applications/$app.app"
  fi
  if ! ditto "$vol/$app.app" "/Applications/$app.app"; then
    err "$app: copy failed — could not install the app"
    hdiutil detach "$vol" -quiet || true
    rm -rf "$tmp"
    return 1
  fi
  if ! hdiutil detach "$vol" -quiet; then
    warn "could not detach $vol"
  fi
  rm -rf "$tmp"
  log "$app: installed to /Applications/$app.app"
}

# Self-updating apps: reinstall only when the bundle is missing.
dmg_update() {
  if ! dmg_installed "$2"; then
    dmg_install "$1" "$2"
  fi
}

# dmg_uninstall bundle-name keep|zap. Zap paths are derived from the app's
# bundle id (read before deletion) — nothing vendor-specific hardcoded here.
dmg_uninstall() {
  local app="$1" mode="${2:-keep}" bid=""
  if ! dmg_installed "$app"; then
    log "$app: not installed, nothing to remove"
    return 0
  fi
  bid="$(defaults read "/Applications/$app.app/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
  run_cmd rm -rf "/Applications/$app.app"
  if [ "$mode" = zap ]; then
    run_cmd rm -rf "$HOME/Library/Application Support/$app"
    if [ -n "$bid" ]; then
      run_cmd rm -rf \
        "$HOME/Library/Preferences/$bid.plist" \
        "$HOME/Library/Caches/$bid" \
        "$HOME/Library/Application Support/$bid"
    fi
  fi
}

# ---- VS Code extensions ------------------------------------------------------

# The visual-studio-code cask links `code` into the brew prefix; a PATH without
# Homebrew (GUI-launched shells) still has the copy inside the app bundle.
vscode_code_bin() {
  local b="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if command -v code >/dev/null 2>&1; then
    command -v code
    return 0
  fi
  if [ -x "$b" ]; then
    printf '%s\n' "$b"
    return 0
  fi
  return 1
}

# vscode_ext_installed id [list]: 0 when the extension is installed. `code
# --list-extensions` prints ids lowercased; pass its (lowercased) output as
# $2 to avoid one CLI call per id.
vscode_ext_installed() {
  local id list code
  id="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  if [ -n "${2+x}" ]; then
    list="$2"
  else
    code="$(vscode_code_bin)" || return 1
    list="$("$code" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  fi
  printf '%s\n' "$list" | grep -Fqx "$id"
}

vscode_ext_install() {
  local code
  if ! code="$(vscode_code_bin)"; then
    err "VS Code: 'code' CLI not found — cannot install extension $1"
    return 1
  fi
  run_cmd "$code" --install-extension "$1"
}

# ---- macOS preferences (`defaults`) ----------------------------------------
# For settings units (hardening, performance) whose "install" is a set of
# system/user preferences. Reads never need root; writes to /Library/... do,
# so callers pass `sudo` explicitly where required.

# pref_is [-currentHost] domain key expected -> 0 if the stored value prints
# as `expected` (booleans print as 1/0). Missing key or domain -> 1.
pref_is() {
  local host=""
  if [ "${1:-}" = -currentHost ]; then host=-currentHost; shift; fi
  # shellcheck disable=SC2086
  [ "$(defaults $host read "$1" "$2" 2>/dev/null)" = "$3" ]
}

# pref_delete [sudo] [-currentHost] domain key -> remove a key only when it is
# present, so reverting a setting never fails on an already-clean machine.
pref_delete() {
  local su="" host=""
  if [ "${1:-}" = sudo ]; then su=sudo; shift; fi
  if [ "${1:-}" = -currentHost ]; then host=-currentHost; shift; fi
  # shellcheck disable=SC2086
  if defaults $host read "$1" "$2" >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    run_cmd $su defaults $host delete "$1" "$2"
  fi
}

# ---- Agent config files (TOML / JSON) --------------------------------------
# For units that pin a setting inside a config file the app itself also
# writes (Codex's config.toml, Gemini CLI's settings.json). Only the named
# key is touched; everything else is passed through as written. Line-based
# on purpose — stock macOS has no TOML library (python3 3.9 lacks tomllib)
# and the files are simple `[table]` / `key = value` documents.

# toml_get file table key -> prints the value of `key` under `[table]` (or of
# a top-level dotted `table.key`), trailing comment and whitespace stripped.
# Prints nothing when unset. Quoted keys, inline tables and arrays of
# tables are not understood; a key inside `[[table]]` is never matched.
toml_get() {
  [ -f "$1" ] || return 1
  awk -v table="$2" -v key="$3" '
    BEGIN { top = 1; intable = 0; found = 0 }
    {
      s = $0; sub(/#.*/, "", s)
      if (s ~ /^[ \t]*\[/) {
        top = 0; intable = 0
        if (s !~ /^[ \t]*\[\[/) {
          h = s; sub(/^[ \t]*\[[ \t]*/, "", h); sub(/[ \t]*\][ \t]*$/, "", h)
          if (h == table) intable = 1
        }
        next
      }
      if (s !~ /=/) next
      k = s; sub(/[ \t]*=.*/, "", k); sub(/^[ \t]*/, "", k)
      v = s; sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t]*$/, "", v)
      if ((intable && k == key) || (top && k == table "." key)) { val = v; found = 1 }
    }
    END { if (found) print val }
  ' "$1"
}

# toml_bool_is file table key true|false -> 0 when set to exactly that.
toml_bool_is() { [ "$(toml_get "$1" "$2" "$3")" = "$4" ]; }

# toml_set_bool file table key true|false. Replaces the key in place when
# `[table]` has it, adds it to the table when not, appends the table when
# the file lacks it, creates the file when missing. A top-level dotted
# `table.key` line is dropped so the table form is not a duplicate key.
toml_set_bool() {
  local file="$1" table="$2" key="$3" value="$4" src tmp
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] set $key = $value in [$table] of $file"
    return 0
  fi
  src="$file"
  [ -f "$src" ] || src=/dev/null
  tmp="$(mktemp)"
  if ! awk -v table="$table" -v key="$key" -v value="$value" '
    function flush() { while (blanks > 0) { print ""; blanks-- } }
    function put(l) { flush(); print l; printed++ }
    function emit() { put(key " = " value); done = 1 }
    BEGIN { top = 1; intable = 0; done = 0; blanks = 0; printed = 0 }
    {
      line = $0
      if (line ~ /^[ \t]*$/) { blanks++; next }
      s = line; sub(/#.*/, "", s)
      if (s ~ /^[ \t]*\[/) {
        if (intable && !done) emit()
        top = 0; intable = 0
        if (s !~ /^[ \t]*\[\[/) {
          h = s; sub(/^[ \t]*\[[ \t]*/, "", h); sub(/[ \t]*\][ \t]*$/, "", h)
          if (h == table) intable = 1
        }
        put(line); next
      }
      if (s ~ /=/) {
        k = s; sub(/[ \t]*=.*/, "", k); sub(/^[ \t]*/, "", k)
        if (intable && k == key) { if (!done) emit(); next }
        if (top && k == table "." key) next
      }
      put(line)
    }
    END {
      if (intable && !done) emit()
      if (!done) { if (printed) print ""; print "[" table "]"; print key " = " value }
    }
  ' "$src" >"$tmp"; then
    rm -f "$tmp"
    err "could not rewrite $file"
    return 1
  fi
  mkdir -p "$(dirname "$file")" || { rm -f "$tmp"; return 1; }
  # cat, not mv: keeps the file's mode and owner as the app set them.
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

# json_get file dotted.path -> prints the JSON encoding of the value at that
# path (e.g. `false`, `"x"`). Nothing and rc 1 when the file is missing,
# unparsable or lacks the path.
json_get() {
  [ -f "$1" ] || return 1
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
for p in sys.argv[2].split("."):
    if not isinstance(d, dict) or p not in d:
        sys.exit(1)
    d = d[p]
print(json.dumps(d))
PY
}

# json_bool_is file dotted.path true|false -> 0 when set to exactly that.
json_bool_is() { [ "$(json_get "$1" "$2" 2>/dev/null)" = "$3" ]; }

# json_set_bool file dotted.path true|false. Creates the file (and missing
# parent objects) as needed; rewrites with 2-space indent. A file that does
# not parse is refused with rc 1 rather than overwritten — comments in a
# JSONC-style settings file count as not parsing.
json_set_bool() {
  local file="$1" path="$2" value="$3"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] set $path = $value in $file"
    return 0
  fi
  mkdir -p "$(dirname "$file")" || return 1
  python3 - "$file" "$path" "$value" <<'PY'
import json, os, sys
f, path, value = sys.argv[1:4]
d = {}
if os.path.exists(f) and os.path.getsize(f) > 0:
    try:
        with open(f) as fh:
            d = json.load(fh)
    except Exception:
        d = None
    if not isinstance(d, dict):
        sys.stderr.write("error: %s is not valid JSON — fix or remove it; nothing was changed\n" % f)
        sys.exit(1)
node = d
parts = path.split(".")
for p in parts[:-1]:
    if not isinstance(node.get(p), dict):
        node[p] = {}
    node = node[p]
node[parts[-1]] = value == "true"
tmp = f + ".tmp"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
os.replace(tmp, f)
PY
}
