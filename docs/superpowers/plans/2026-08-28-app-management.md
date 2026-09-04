# App Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Selectable install/update/uninstall management for 10 macOS apps via `run.sh` (interactive + non-interactive) and `update.sh`, with per-machine selection stored in a gitignored, hostname-keyed config.

**Architecture:** Plain bash. Each app is one script in `apps/` implementing a standard function contract; shared drivers (`brew cask`, `brew formula`, `direct dmg`) live in `lib/drivers.sh`; `lib/common.sh` holds logging/dry-run/config/discovery plumbing; `lib/ui.sh` holds the interactive checklist. `run.sh` reconciles saved selection vs. new selection (install added, update kept, uninstall removed); `update.sh` updates the saved selection.

**Tech Stack:** bash 3.2 (macOS stock), Homebrew, curl/hdiutil/ditto for dmg installs, shellcheck for linting.

**Spec:** `docs/superpowers/specs/2026-08-28-app-management-design.md`

## Global Constraints

- Must run on stock macOS `/bin/bash` **3.2**: no associative arrays, no `${var,,}`, no `mapfile`. Selections are space-separated strings; app metadata uses parallel indexed arrays.
- `set -euo pipefail` in entry points (`run.sh`, `update.sh`). Library files are sourced and must not `set -e` themselves. Because of `set -e`, never end a function or script with a bare `[ ... ] && cmd` — always use `if`.
- All mutating commands go through `run_cmd` so `--dry-run` (env `DRY_RUN=1`) covers everything; dry-run output lines start with `[dry-run] `.
- Per-machine config: `local/$(hostname -s).conf`; `local/` is gitignored. Config dir overridable via `BOOTSTRAP_CONFIG_DIR` env var (used by verification steps).
- App ids are the `apps/*.sh` filenames minus `.sh`. Function names replace hyphens with underscores: `little-snitch` → `little_snitch_install`.
- Every `apps/<id>.sh` defines: `APP_NAME` (display name), optional `APP_NOTE` (post-install note), and functions `<id>_install`, `<id>_update`, `<id>_uninstall <keep|zap>`, `<id>_installed`.
- `shellcheck` clean on every `.sh` file. Dynamic sourcing needs `# shellcheck source=/dev/null`; intentional word-splitting of id lists needs `# shellcheck disable=SC2086` on that line.
- Managed app set (10): chrome, firefox, little-snitch, controld, claude, claude-code, gemini, gemini-cli, chatgpt, maccy. **Grok is excluded** (no official macOS distribution — see spec).
- Homebrew is infrastructure: installed when missing, never uninstalled by selection.
- Repo root scripts `run.sh` / `update.sh` are executable (`chmod +x`); `lib/` and `apps/` files are sourced, not executable.
- All shell verification commands below are run from the repo root (the local checkout of this repo).
- No test framework (per spec). Each task verifies via shellcheck + concrete dry-run/function invocations with expected output shown.
- If `shellcheck` is not installed, install it first with `brew install shellcheck`.

---

### Task 1: Core plumbing — `lib/common.sh` + `.gitignore`

**Files:**
- Create: `lib/common.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing (foundation).
- Produces (used by every later task):
  - `log msg...` / `warn msg...` / `err msg...` — stdout / stderr(+`warning:`) / stderr(+`error:`)
  - `DRY_RUN` (env, default `0`); `run_cmd cmd args...` — executes, or prints `[dry-run] cmd args...` when `DRY_RUN=1`
  - `in_list item list` — 0 if space-separated `list` contains `item`
  - `remove_from_list item list` — prints `list` without `item`
  - `CONFIG_DIR`; `config_file` — prints `$CONFIG_DIR/$(hostname -s).conf`
  - `load_config` — sets `SELECTED` (space-separated string, `""` default); returns 1 when no config file
  - `save_config` — writes `SELECTED=` line to `config_file`
  - `ensure_homebrew` — installs brew if missing, puts it on PATH for this process
  - `discover_apps` — sources every `apps/*.sh`; fills parallel arrays `APP_IDS`, `APP_NAMES`, `APP_NOTES`; errors if `apps/` is empty
  - `app_name_for id` / `app_note_for id` — print display name / note (empty string when no note)
  - `app_fn id suffix` — prints function name, e.g. `app_fn little-snitch update` → `little_snitch_update`
  - `validate_selection list` — exit 2 naming the bad id and listing valid ids

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Per-machine selection config — never committed (and hostname-keyed so
# Dropbox sync between machines cannot clobber it).
local/
```

- [ ] **Step 2: Write `lib/common.sh`**

```bash
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

CONFIG_DIR="${BOOTSTRAP_CONFIG_DIR:-$REPO_ROOT/local}"

config_file() { printf '%s/%s.conf\n' "$CONFIG_DIR" "$(hostname -s)"; }

# Sets SELECTED from this machine's config; SELECTED="" and return 1 if absent.
load_config() {
  SELECTED=""
  local cf
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
```

- [ ] **Step 3: Lint**

Run: `shellcheck lib/common.sh`
Expected: no output (exit 0).

- [ ] **Step 4: Functional check (dry-run, list helpers, config round-trip)**

Run:
```bash
bash -c '
set -euo pipefail
REPO_ROOT="$PWD"
BOOTSTRAP_CONFIG_DIR="$(mktemp -d)"
export BOOTSTRAP_CONFIG_DIR
. lib/common.sh
DRY_RUN=1 run_cmd brew install --cask fake-app
in_list b "a b c" && echo "in_list: ok"
in_list z "a b c" || echo "not-in_list: ok"
echo "removed: [$(remove_from_list b "a b c")]"
load_config || echo "no config yet: ok"
SELECTED="chrome maccy"
save_config
SELECTED=""
load_config
echo "roundtrip: [$SELECTED]"
'
```
Expected output (config path varies):
```
[dry-run] brew install --cask fake-app
in_list: ok
not-in_list: ok
removed: [ a c]
no config yet: ok
saved selection to /var/folders/.../<hostname>.conf
roundtrip: [chrome maccy]
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore lib/common.sh
git commit -m "feat: add core plumbing lib/common.sh and gitignore local/"
```

---

### Task 2: Install drivers — `lib/drivers.sh`

**Files:**
- Create: `lib/drivers.sh`

**Interfaces:**
- Consumes (Task 1): `run_cmd`, `log`, `err`, `DRY_RUN`.
- Produces (used by all `apps/*.sh`):
  - `cask_install name` / `cask_update name` / `cask_uninstall name keep|zap` / `cask_installed name`
  - `formula_install name` / `formula_update name` / `formula_uninstall name keep|zap` / `formula_installed name`
  - `dmg_install url bundle-name` / `dmg_update url bundle-name` / `dmg_uninstall bundle-name keep|zap` / `dmg_installed bundle-name` (bundle-name is without `.app`)

- [ ] **Step 1: Write `lib/drivers.sh`**

```bash
#!/bin/bash
# Install/update/uninstall drivers shared by apps/*.sh.
# Sourced after lib/common.sh (uses run_cmd/log/err/DRY_RUN).

# ---- Homebrew cask ----------------------------------------------------------

cask_installed() { brew list --cask "$1" >/dev/null 2>&1; }

# --adopt takes over an app the user already installed manually.
cask_install() { run_cmd brew install --cask --adopt "$1"; }

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

cask_uninstall() {
  if ! cask_installed "$1"; then
    log "$1: not installed via brew, nothing to remove"
    return 0
  fi
  if [ "${2:-keep}" = zap ]; then
    run_cmd brew uninstall --cask --zap "$1"
  else
    run_cmd brew uninstall --cask "$1"
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
  ditto "$vol/$app.app" "/Applications/$app.app"
  hdiutil detach "$vol" -quiet
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
```

- [ ] **Step 2: Lint**

Run: `shellcheck lib/drivers.sh`
Expected: no output (exit 0).

- [ ] **Step 3: Functional check (dry-run paths only — must not touch the system)**

Run:
```bash
bash -c '
set -euo pipefail
REPO_ROOT="$PWD"
. lib/common.sh
. lib/drivers.sh
export DRY_RUN=1
cask_install google-chrome
cask_uninstall not-a-real-cask keep
formula_install gemini-cli
dmg_install "https://example.com/x.dmg" "Fake App"
dmg_update "https://example.com/x.dmg" "Fake App"
dmg_uninstall "Fake App" zap
'
```
Expected output:
```
[dry-run] brew install --cask --adopt google-chrome
not-a-real-cask: not installed via brew, nothing to remove
[dry-run] brew install gemini-cli
[dry-run] download https://example.com/x.dmg and install /Applications/Fake App.app
[dry-run] download https://example.com/x.dmg and install /Applications/Fake App.app
Fake App: not installed, nothing to remove
```
(`dmg_update` re-prints the install line because "Fake App" is absent; `dmg_uninstall` no-ops for the same reason.)

- [ ] **Step 4: Commit**

```bash
git add lib/drivers.sh
git commit -m "feat: add brew cask/formula and direct-dmg drivers"
```

---

### Task 3: App definitions — `apps/*.sh` (10 files)

**Files:**
- Create: `apps/chrome.sh`, `apps/firefox.sh`, `apps/little-snitch.sh`, `apps/controld.sh`, `apps/claude.sh`, `apps/claude-code.sh`, `apps/gemini.sh`, `apps/gemini-cli.sh`, `apps/chatgpt.sh`, `apps/maccy.sh`

**Interfaces:**
- Consumes (Task 2 drivers; Task 1 discovery contract).
- Produces: per app id `<id>`: `APP_NAME`, optional `APP_NOTE`, and `<id>_install` / `<id>_update` / `<id>_uninstall <keep|zap>` / `<id>_installed` (hyphens → underscores in function names). Consumed by `run.sh`/`update.sh` via `app_fn`.

- [ ] **Step 1: Write the eight brew-cask app files**

`apps/chrome.sh`:
```bash
#!/bin/bash
# Google Chrome — Homebrew cask (auto-updates itself once installed).
APP_NAME="Google Chrome"

chrome_install()   { cask_install google-chrome; }
chrome_update()    { cask_update google-chrome; }
chrome_uninstall() { cask_uninstall google-chrome "$1"; }
chrome_installed() { cask_installed google-chrome; }
```

`apps/firefox.sh`:
```bash
#!/bin/bash
# Mozilla Firefox — Homebrew cask.
APP_NAME="Firefox"

firefox_install()   { cask_install firefox; }
firefox_update()    { cask_update firefox; }
firefox_uninstall() { cask_uninstall firefox "$1"; }
firefox_installed() { cask_installed firefox; }
```

`apps/little-snitch.sh`:
```bash
#!/bin/bash
# Little Snitch — Homebrew cask. Needs a manual one-time system-extension
# approval after install; license/rules are never touched by this repo.
APP_NAME="Little Snitch"
APP_NOTE="Approve the Little Snitch system extension in System Settings > General > Login Items & Extensions, then enter your license."

little_snitch_install()   { cask_install little-snitch; }
little_snitch_update()    { cask_update little-snitch; }
little_snitch_uninstall() { cask_uninstall little-snitch "$1"; }
little_snitch_installed() { cask_installed little-snitch; }
```

`apps/claude.sh`:
```bash
#!/bin/bash
# Claude Desktop — Homebrew cask (auto-updates itself once installed).
APP_NAME="Claude Desktop"

claude_install()   { cask_install claude; }
claude_update()    { cask_update claude; }
claude_uninstall() { cask_uninstall claude "$1"; }
claude_installed() { cask_installed claude; }
```

`apps/claude-code.sh`:
```bash
#!/bin/bash
# Claude Code CLI — Homebrew cask.
APP_NAME="Claude Code"

claude_code_install()   { cask_install claude-code; }
claude_code_update()    { cask_update claude-code; }
claude_code_uninstall() { cask_uninstall claude-code "$1"; }
claude_code_installed() { cask_installed claude-code; }
```

`apps/gemini.sh`:
```bash
#!/bin/bash
# Google Gemini desktop app (gemini.google/mac) — Homebrew cask google-gemini.
APP_NAME="Google Gemini Desktop"

gemini_install()   { cask_install google-gemini; }
gemini_update()    { cask_update google-gemini; }
gemini_uninstall() { cask_uninstall google-gemini "$1"; }
gemini_installed() { cask_installed google-gemini; }
```

`apps/gemini-cli.sh`:
```bash
#!/bin/bash
# Google Gemini CLI — Homebrew formula.
APP_NAME="Gemini CLI"

gemini_cli_install()   { formula_install gemini-cli; }
gemini_cli_update()    { formula_update gemini-cli; }
gemini_cli_uninstall() { formula_uninstall gemini-cli "$1"; }
gemini_cli_installed() { formula_installed gemini-cli; }
```

`apps/chatgpt.sh`:
```bash
#!/bin/bash
# OpenAI ChatGPT desktop — Homebrew cask (auto-updates itself once installed).
APP_NAME="ChatGPT"

chatgpt_install()   { cask_install chatgpt; }
chatgpt_update()    { cask_update chatgpt; }
chatgpt_uninstall() { cask_uninstall chatgpt "$1"; }
chatgpt_installed() { cask_installed chatgpt; }
```

`apps/maccy.sh`:
```bash
#!/bin/bash
# Maccy clipboard manager — Homebrew cask.
APP_NAME="Maccy"

maccy_install()   { cask_install maccy; }
maccy_update()    { cask_update maccy; }
maccy_uninstall() { cask_uninstall maccy "$1"; }
maccy_installed() { cask_installed maccy; }
```

- [ ] **Step 2: Write `apps/controld.sh` (direct dmg, arch-dependent URL)**

```bash
#!/bin/bash
# Control D GUI Setup Utility — no Homebrew cask; installed from the vendor
# dmg (URL verified 2026-08-28). The utility self-updates, so update only
# reinstalls when the app is missing.
APP_NAME="Control D"
APP_NOTE="Open 'Control D Utility App' and sign in to finish DNS setup (resolver config is per-machine, not managed by this repo)."

CONTROLD_BUNDLE="Control D Utility App"

controld_url() {
  if [ "$(uname -m)" = arm64 ]; then
    printf 'https://assets.controld.com/utility/controld_arm.dmg\n'
  else
    printf 'https://assets.controld.com/utility/controld_x86.dmg\n'
  fi
}

controld_install()   { dmg_install "$(controld_url)" "$CONTROLD_BUNDLE"; }
controld_update()    { dmg_update "$(controld_url)" "$CONTROLD_BUNDLE"; }
controld_uninstall() { dmg_uninstall "$CONTROLD_BUNDLE" "$1"; }
controld_installed() { dmg_installed "$CONTROLD_BUNDLE"; }
```

- [ ] **Step 3: Lint all app files**

Run: `shellcheck apps/*.sh`
Expected: no output (exit 0).

- [ ] **Step 4: Functional check — discovery finds all 10, functions resolve, dry-run installs print**

Run:
```bash
bash -c '
set -euo pipefail
REPO_ROOT="$PWD"
. lib/common.sh
. lib/drivers.sh
discover_apps
echo "count: ${#APP_IDS[@]}"
echo "ids: ${APP_IDS[*]}"
export DRY_RUN=1
for id in "${APP_IDS[@]}"; do
  fn="$(app_fn "$id" install)"
  type "$fn" >/dev/null 2>&1 || { echo "MISSING: $fn"; exit 1; }
  "$fn"
done
echo "note check: [$(app_note_for little-snitch | cut -c1-7)]"
'
```
Expected output — line order follows the glob's locale collation, so hyphenated ids may sort before or after their prefix (`claude-code` vs `claude`); verify **content**, not order:
```
count: 10
ids: <all 10 ids, one occurrence each>
[dry-run] brew install --cask --adopt chatgpt
[dry-run] brew install --cask --adopt google-chrome
[dry-run] brew install --cask --adopt claude
[dry-run] brew install --cask --adopt claude-code
[dry-run] download https://assets.controld.com/utility/controld_arm.dmg and install /Applications/Control D Utility App.app
[dry-run] brew install --cask --adopt firefox
[dry-run] brew install --cask --adopt google-gemini
[dry-run] brew install gemini-cli
[dry-run] brew install --cask --adopt little-snitch
[dry-run] brew install --cask --adopt maccy
note check: [Approve]
```
Checks that matter: exactly 10 ids; `gemini-cli` uses `brew install` **without** `--cask` (formula); the controld line shows `controld_x86.dmg` on Intel Macs; no `MISSING:` lines.

- [ ] **Step 5: Commit**

```bash
git add apps/
git commit -m "feat: add per-app management scripts for the 10 managed apps"
```

---

### Task 4: Interactive UI — `lib/ui.sh`

**Files:**
- Create: `lib/ui.sh`

**Interfaces:**
- Consumes (Task 1): `APP_IDS`, `APP_NAMES`, `SELECTED`, `in_list`, `remove_from_list`, `log`, `warn`.
- Produces (used by `run.sh`):
  - `select_apps` — interactive checklist seeded from `$SELECTED`; on confirm sets `NEW_SELECTED` (space-separated ids)
  - `prompt_uninstall_mode display-name` — prompts on stderr, prints `keep` or `zap` on stdout

- [ ] **Step 1: Write `lib/ui.sh`**

```bash
#!/bin/bash
# Interactive selection UI. Sourced after lib/common.sh; needs discover_apps
# to have populated APP_IDS/APP_NAMES.

# Checklist over all discovered apps, pre-checked from $SELECTED.
# Toggle by number, a=all, n=none, empty input confirms into NEW_SELECTED.
select_apps() {
  local current="$SELECTED" input tok idx id
  while :; do
    log ""
    log "Select apps to manage. Checked apps are installed and kept updated;"
    log "unchecking a previously managed app uninstalls it."
    idx=0
    while [ "$idx" -lt "${#APP_IDS[@]}" ]; do
      id="${APP_IDS[$idx]}"
      if in_list "$id" "$current"; then
        printf '  %2d) [x] %s\n' "$((idx + 1))" "${APP_NAMES[$idx]}"
      else
        printf '  %2d) [ ] %s\n' "$((idx + 1))" "${APP_NAMES[$idx]}"
      fi
      idx=$((idx + 1))
    done
    printf 'Toggle numbers (space-separated), a=all, n=none, Enter=confirm: '
    read -r input
    case "$input" in
      "")
        NEW_SELECTED="$current"
        return 0
        ;;
      a) current="${APP_IDS[*]}" ;;
      n) current="" ;;
      *)
        # shellcheck disable=SC2086
        for tok in $input; do
          case "$tok" in
            *[!0-9]*)
              warn "not a number: $tok"
              ;;
            *)
              if [ "$tok" -ge 1 ] && [ "$tok" -le "${#APP_IDS[@]}" ]; then
                id="${APP_IDS[$((tok - 1))]}"
                if in_list "$id" "$current"; then
                  current="$(remove_from_list "$id" "$current")"
                else
                  current="$current $id"
                fi
              else
                warn "out of range: $tok"
              fi
              ;;
          esac
        done
        ;;
    esac
  done
}

# Ask keep-vs-zap for one app being uninstalled. Prompt goes to stderr so the
# answer can be captured from stdout. Default (Enter or anything but z) = keep.
prompt_uninstall_mode() {
  local ans
  printf 'Remove %s — keep its settings? [K=keep / z=zap settings too]: ' "$1" >&2
  read -r ans
  case "$ans" in
    z | Z | zap) printf 'zap\n' ;;
    *) printf 'keep\n' ;;
  esac
}
```

- [ ] **Step 2: Lint**

Run: `shellcheck lib/ui.sh`
Expected: no output (exit 0).

- [ ] **Step 3: Functional check with scripted stdin**

Toggle app 2 on, then app 2 off again, toggle 1 and 3 on, confirm; then answer `z` to an uninstall prompt:

Run:
```bash
bash -c '
set -euo pipefail
REPO_ROOT="$PWD"
. lib/common.sh
. lib/drivers.sh
. lib/ui.sh
discover_apps
SELECTED=""
printf "2\n2\n1 3\n\n" | select_apps >/dev/null
echo "selected: [$NEW_SELECTED]"
echo "mode: $(printf "z\n" | prompt_uninstall_mode "Test App" 2>/dev/null)"
echo "mode-default: $(printf "\n" | prompt_uninstall_mode "Test App" 2>/dev/null)"
'
```
Expected output — the two selected ids are whatever apps sit at positions 1 and 3 in this machine's glob order (with C-locale byte order that's `chatgpt` and `claude`; collation may differ). What must hold: exactly two ids (position 2 was toggled on then off), and the two mode lines:
```
selected: [ <id-at-1> <id-at-3>]
mode: zap
mode-default: keep
```

- [ ] **Step 4: Commit**

```bash
git add lib/ui.sh
git commit -m "feat: add interactive app-selection checklist and uninstall prompt"
```

---

### Task 5: Entry point — `run.sh`

**Files:**
- Create: `run.sh` (executable)

**Interfaces:**
- Consumes: everything from Tasks 1–4, plus existing `install.sh`.
- Produces: the user-facing `./run.sh` CLI: `--non-interactive`, `--apps LIST` (comma-separated; `none` = empty selection), `--dry-run`, `--help`.

- [ ] **Step 1: Write `run.sh`**

```bash
#!/bin/bash
# Entry point: bootstrap Homebrew + dotfiles, choose managed apps, reconcile.
# Interactive by default; see --help for non-interactive use.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$REPO_ROOT/lib/common.sh"
. "$REPO_ROOT/lib/drivers.sh"
. "$REPO_ROOT/lib/ui.sh"

usage() {
  cat <<'EOF'
Usage: run.sh [--non-interactive] [--apps id1,id2,...] [--dry-run] [--help]

Installs Homebrew (if missing) and the repo dotfiles, then reconciles this
machine's managed apps: newly selected apps are installed, still-selected apps
are updated, deselected apps are uninstalled. The selection is saved to
local/<hostname>.conf (gitignored).

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
  fi
done

if [ "$DRY_RUN" = 1 ]; then
  log "[dry-run] save selection [$NEW_SELECTED] to $(config_file)"
else
  SELECTED="$NEW_SELECTED"
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
```

- [ ] **Step 2: Make executable and lint**

Run: `chmod +x run.sh && shellcheck run.sh`
Expected: no output (exit 0).

- [ ] **Step 3: Functional check — dry-run, isolated config, full lifecycle**

Run (config isolated to a temp dir; nothing touches the system):
```bash
CFG="$(mktemp -d)"
export BOOTSTRAP_CONFIG_DIR="$CFG"
./run.sh --dry-run --apps chrome,maccy
echo "--- non-interactive without config:"
./run.sh --non-interactive --dry-run || echo "exit=$? (expected 1)"
echo "--- real save then reconcile with removal prompt:"
printf 'SELECTED="chrome maccy"\n' > "$CFG/$(hostname -s).conf"
printf 'z\n' | ./run.sh --dry-run --apps chrome,gemini-cli
unset BOOTSTRAP_CONFIG_DIR
```
Expected key lines from the first invocation:
```
[dry-run] ./install.sh (dotfile symlinks)
== installing Google Chrome
[dry-run] brew install --cask --adopt google-chrome
== installing Maccy
[dry-run] brew install --cask --adopt maccy
[dry-run] save selection [chrome maccy] to .../<hostname>.conf
Summary:
  installed: chrome maccy
```
Second invocation: `error: no saved selection at ...` then `exit=1 (expected 1)`.
Third invocation: `== updating Google Chrome`, `== installing Gemini CLI`, `== removing Maccy (settings: zap)` with `[dry-run] brew uninstall --cask --zap maccy` — **note** `cask_update`/`cask_uninstall` consult the real brew state, so on a machine where chrome/maccy aren't brew-installed the update path prints an install line and the removal prints `maccy: not installed via brew, nothing to remove` instead; both are acceptable.

- [ ] **Step 4: Verify `--help` and bad input**

Run: `./run.sh --help | head -3 && ./run.sh --apps nope --dry-run; echo "exit=$?"`
Expected: usage text; then `error: unknown app id: nope (valid: <all 10 ids>)` and `exit=2`.

- [ ] **Step 5: Commit**

```bash
git add run.sh
git commit -m "feat: add run.sh entry point with selection reconciliation"
```

---

### Task 6: Updater — `update.sh`

**Files:**
- Create: `update.sh` (executable)

**Interfaces:**
- Consumes: Tasks 1–3 (`load_config`, `discover_apps`, `app_fn`, drivers), `ensure_homebrew`.
- Produces: `./update.sh [--dry-run] [--help]` — updates Homebrew and every app in this machine's saved selection.

- [ ] **Step 1: Write `update.sh`**

```bash
#!/bin/bash
# Update Homebrew and every app in this machine's saved selection.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$REPO_ROOT/lib/common.sh"
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
```

- [ ] **Step 2: Make executable and lint**

Run: `chmod +x update.sh && shellcheck update.sh`
Expected: no output (exit 0).

- [ ] **Step 3: Functional check (isolated config, dry-run)**

Run:
```bash
CFG="$(mktemp -d)"
export BOOTSTRAP_CONFIG_DIR="$CFG"
./update.sh --dry-run || echo "exit=$? (expected 1, no config)"
printf 'SELECTED="controld gemini-cli"\n' > "$CFG/$(hostname -s).conf"
./update.sh --dry-run
printf 'SELECTED=""\n' > "$CFG/$(hostname -s).conf"
./update.sh --dry-run
unset BOOTSTRAP_CONFIG_DIR
```
Expected: first run errors `no saved selection ... run ./run.sh first`, `exit=1`. Second run prints `[dry-run] brew update`, `== updating Control D` (then either nothing if Control D is installed, or the dry-run download line), `== updating Gemini CLI` (`[dry-run] brew install gemini-cli` if the formula is absent), and `Summary: updated: controld gemini-cli`. Third run prints `no apps selected on this machine; nothing to update`.

- [ ] **Step 4: Commit**

```bash
git add update.sh
git commit -m "feat: add update.sh for updating managed apps"
```

---

### Task 7: Documentation — README + managed-apps table

**Files:**
- Modify: `README.md` (add sections; keep existing content)

**Interfaces:**
- Consumes: the CLI surface from Tasks 5–6 (flag names, config path — copy them exactly).
- Produces: user-facing docs; no code.

- [ ] **Step 1: Update `README.md`**

Replace the "Setup on a new machine" section with:

```markdown
## Setup on a new machine

1. Clone the repo. (Historical: this plan predates the git-clone distribution
   model and the curl-able standalone `run.sh` of 2026-09-03.)
2. Run `./run.sh` from the checkout and pick
   the apps this machine should manage.

`run.sh` installs Homebrew if needed, links the managed dotfiles (via
`install.sh`), then installs/updates the selected apps. Re-run it any time to
change the selection — deselected apps are uninstalled (you choose per app
whether their settings are kept or zapped).

Non-interactive use:

```sh
./run.sh --non-interactive            # reuse this machine's saved selection
./run.sh --apps chrome,maccy          # set the exact selection without prompts
./run.sh --apps none                  # uninstall everything managed
./run.sh --dry-run --apps chrome      # print actions without executing
./update.sh                           # update Homebrew + all selected apps
```
```

Append after the "Managed files" table:

```markdown
## Managed apps

Selected per machine via `run.sh`; the selection lives in
`local/<hostname>.conf` (gitignored — the repo holds only automation, never a
machine's configuration; hostname keying keeps Dropbox sync from clobbering
other machines).

| App id | App | How |
|---|---|---|
| `chrome` | Google Chrome | brew cask `google-chrome` (self-updates) |
| `firefox` | Firefox | brew cask `firefox` |
| `little-snitch` | Little Snitch | brew cask `little-snitch`; system-extension approval + license are manual |
| `controld` | Control D GUI utility | vendor dmg from assets.controld.com (self-updates) |
| `claude` | Claude Desktop | brew cask `claude` (self-updates) |
| `claude-code` | Claude Code | brew cask `claude-code` |
| `gemini` | Google Gemini Desktop | brew cask `google-gemini` (self-updates) |
| `gemini-cli` | Gemini CLI | brew formula `gemini-cli` |
| `chatgpt` | ChatGPT | brew cask `chatgpt` (self-updates) |
| `maccy` | Maccy | brew cask `maccy` |

Grok has no official macOS app (no cask, no Mac App Store app, no dmg as of
2026-08-28) and is web-only for now. To add a new app later: drop an
`apps/<id>.sh` implementing `<id>_install/_update/_uninstall/_installed`
(hyphens become underscores) — nothing else to register.

`update.sh` updates Homebrew plus only the selected apps; casks marked
self-updating are left to their own updaters unless missing.
```

- [ ] **Step 2: Verify docs match reality**

Run: `grep -c 'apps/' README.md && ./run.sh --help >/dev/null && echo help-ok`
Expected: a non-zero count and `help-ok`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document run.sh/update.sh app management in README"
```

---

### Task 8: End-to-end verification (manual, real system)

No new files. This task exercises the real flow on this machine — it mutates the system only in ways the user asked for (managing apps).

- [ ] **Step 1: Full dry-run against the real config path**

Run: `./run.sh --dry-run --apps maccy,gemini-cli`
Expected: dotfile dry-run line, install/update lines for both apps, dry-run save line, clean summary, exit 0. Confirm nothing was written: `ls local/ 2>/dev/null` shows no `.conf` created by a dry run.

- [ ] **Step 2: Real minimal run (safe, small apps)**

Run: `./run.sh --apps maccy,gemini-cli`
Expected: Maccy and gemini-cli actually install (brew output), `local/<hostname>.conf` now contains `SELECTED="maccy gemini-cli"`, summary lists both under `installed:`.

- [ ] **Step 3: Idempotency + updater**

Run: `./run.sh --non-interactive` then `./update.sh`
Expected: both exit 0; apps show under `updated:`; no reinstalls.

- [ ] **Step 4: Deselection uninstalls**

Run: `printf '\n' | ./run.sh --apps gemini-cli` (Enter answers "keep" if prompted — `--apps` alone still prompts per removal)
Expected: Maccy uninstalled via brew, config now `SELECTED="gemini-cli"`, summary shows `removed: maccy`.

- [ ] **Step 5: Git status clean of machine state**

Run: `git status --porcelain`
Expected: empty — `local/` is ignored; no machine-specific files tracked.

- [ ] **Step 6: Restore the user's desired state**

Re-run `./run.sh` interactively so the user's actual selection for this machine is what's saved (or leave `--apps gemini-cli` state and tell the user to run `./run.sh` — report what state the machine was left in).
