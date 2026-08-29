# App Management Design

**Date:** 2026-08-28
**Status:** Approved design, pending implementation

## Goal

Extend claude-mac-bootstrap so a Mac — new or already in use — can clone/sync the
repo and run `./run.sh` (interactively or non-interactively) to select which managed
apps it wants. Selected apps are installed and kept updated on every run; deselected
apps are uninstalled. `./update.sh` updates everything currently managed. The repo
holds only automation; each machine's selection lives in a gitignored, hostname-keyed
local config file.

## Managed apps (initial set)

| App id | Display name | Method | Source |
|---|---|---|---|
| `chrome` | Google Chrome | brew cask | `google-chrome` |
| `firefox` | Firefox | brew cask | `firefox` |
| `little-snitch` | Little Snitch | brew cask | `little-snitch` |
| `controld` | Control D (GUI) | direct dmg | `https://assets.controld.com/utility/controld_{arm,x86}.dmg` by arch; installs `Control D Utility App.app` |
| `claude` | Claude Desktop | brew cask | `claude` |
| `claude-code` | Claude Code | brew cask | `claude-code` |
| `gemini` | Google Gemini Desktop | brew cask | `google-gemini` |
| `gemini-cli` | Gemini CLI | brew formula | `gemini-cli` |
| `chatgpt` | ChatGPT | brew cask | `chatgpt` |
| `maccy` | Maccy | brew cask | `maccy` |

**Grok is excluded** (decided 2026-08-28): xAI ships no official macOS
distribution — no cask, no Mac App Store app (the App Store "Grok AI" is
iOS/iPadOS-only), no dmg. Revisit if xAI releases a desktop app; adding it back
is one new `apps/grok.sh` file. README notes it as web-only.

**Homebrew** is required infrastructure, not a selectable app: `run.sh` installs it
when missing; `update.sh` runs `brew update` + upgrades. It is never uninstalled by
deselection (deselecting it would orphan every cask-managed app).

## Repository layout

```
run.sh                  # entry point: brew bootstrap, install.sh, selection, reconcile
update.sh               # update all currently-managed apps
install.sh              # existing dotfile symlinker (unchanged; called by run.sh)
apps/
  chrome.sh             # one script per app, standard interface (see below)
  firefox.sh
  little-snitch.sh
  controld.sh
  claude.sh
  claude-code.sh
  gemini.sh
  gemini-cli.sh
  chatgpt.sh
  maccy.sh
lib/
  common.sh             # logging, dry-run plumbing, config load/save, brew bootstrap
  drivers.sh            # shared install/update/uninstall drivers: brew cask, brew formula, direct dmg
  ui.sh                 # interactive checklist and per-app uninstall prompts
local/                  # gitignored; per-machine config (see below)
```

## Per-app script contract

Every `apps/<id>.sh` is sourced by the engine and defines the same interface.
App id = filename without `.sh`. Function names are prefixed with the app id
(hyphens mapped to underscores) so all app scripts can be sourced together:

```bash
# apps/chrome.sh
APP_NAME="Google Chrome"

chrome_install()   { cask_install google-chrome; }
chrome_update()    { cask_update google-chrome; }
chrome_uninstall() { cask_uninstall google-chrome "$1"; }  # $1 = "zap" or "keep"
chrome_installed() { cask_installed google-chrome; }
```

- Brew-based apps delegate to `lib/drivers.sh` one-liners (`cask_*`, `formula_*`).
- Direct-dmg apps (`controld`) delegate to `dmg_*` drivers with their
  download URL and `.app` bundle name; anything vendor-specific stays in that
  app's file.
- The engine discovers apps by globbing `apps/*.sh` — adding an app to the system
  means adding one file, nothing else.
- `APP_NAME` is set before sourcing-time capture by the engine (each file is
  sourced in sequence; the engine records `APP_NAME` per file into a lookup map).

## Drivers (`lib/drivers.sh`)

- **brew cask**: `cask_install` uses `brew install --cask --adopt` so an app the
  user already installed manually is taken over instead of erroring.
  `cask_update` uses `brew upgrade --cask` (no-op when current).
  `cask_uninstall` uses `brew uninstall --cask` plus `--zap` when asked.
- **brew formula**: same shape via `brew install` / `brew upgrade` /
  `brew uninstall`.
- **direct dmg**: download to a temp dir with `curl -fL`, attach with
  `hdiutil attach -nobrowse`, `ditto` the `.app` into `/Applications`, detach,
  clean up. Install fails loudly with a manual-download hint if the URL breaks.
  The Control D utility self-updates, so `dmg_update` only reinstalls when
  the app bundle is missing from `/Applications`. Uninstall removes the `.app`;
  zap additionally removes the app's `~/Library` preference/support paths listed
  in the app's script.

## Per-machine config

- Path: `local/$(hostname -s).conf`; `local/` is gitignored.
- Rationale: a plain gitignored file would still sync via Dropbox to every
  machine and be clobbered; hostname keying makes Dropbox sync a feature — a
  machine's selection survives reinstall.
- Format: plain bash, sourced by the engine:

  ```bash
  # managed by run.sh — do not sync between machines
  SELECTED="chrome firefox claude-code maccy"
  ```

- The saved `SELECTED` list doubles as the record of what is currently managed:
  reconciliation diffs saved selection vs. new selection.

## run.sh flow

1. Parse flags: `--non-interactive`, `--apps id1,id2,...`, `--dry-run`, `--help`.
2. Install Homebrew if missing (official installer); ensure brew is on PATH for
   the current process.
3. Run `install.sh` (existing dotfile symlinks) so `run.sh` is the single
   new-machine entry point.
4. Determine the new selection:
   - Interactive (default): checklist UI listing every app from `apps/*.sh`,
     pre-checked from saved config (first run: none checked), toggle by number,
     confirm to proceed.
   - `--non-interactive`: use saved config as-is; error with guidance if no
     config exists and `--apps` was not given.
   - `--apps chrome,firefox`: sets the exact selection (works with or without
     `--non-interactive`); unknown ids are an error listing valid ids.
5. Reconcile:
   - Newly selected → `<id>_install`, then `<id>_update` (covers already-present
     but outdated installs adopted via `--adopt`).
   - Still selected → `<id>_update`.
   - Deselected (in saved config, not in new selection) → `<id>_uninstall`.
     Interactive: per-app prompt — keep settings or zap. Non-interactive: keep
     settings (app-only uninstall).
6. Save the new selection to `local/<hostname>.conf`.
7. Print a summary: installed / updated / removed, plus post-install
   notes (e.g. Little Snitch requires manual system-extension approval in
   System Settings; App/daemon sign-ins are manual).

Idempotent throughout: re-running with an unchanged selection just updates.

## update.sh flow

1. Load `local/<hostname>.conf`; exit with guidance if missing (run `run.sh` first).
2. `brew update`.
3. For each selected app: `<id>_update`. Brew upgrades touch only managed
   casks/formulas — never the machine's unrelated brew packages.
4. Supports `--dry-run`. Summary at the end.

## Error handling

- `set -euo pipefail` everywhere; per-app failures are caught, reported in the
  summary, and don't abort the remaining apps.
- Direct-download failures name the app, the URL tried, and the vendor page for
  manual install.
- Uninstall of an app that is absent is a no-op, not an error.

## Testing

- `--dry-run` on both `run.sh` and `update.sh` prints every action without
  executing (implemented in the drivers, so coverage is total).
- All scripts pass `shellcheck`.
- Manual verification: fresh-run selection, re-run idempotency, deselect →
  uninstall prompt, non-interactive paths.

## Out of scope (YAGNI)

- Scheduling automatic updates (manual `update.sh` only, per requirements).
- Managing app *settings/licenses* (Control D resolver config, Little Snitch
  rules, sign-ins) — install/update/remove only.
- Mac App Store (`mas`) support — no current app needs it.
