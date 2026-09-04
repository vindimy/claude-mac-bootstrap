# App Management Design

**Date:** 2026-08-28
**Status:** Approved design, pending implementation

## Goal

Extend claude-mac-bootstrap so a Mac — new or already in use — can run
`./run.sh` (interactively or non-interactively) to select which managed apps
it wants. A lone curl-ed copy of `run.sh` bootstraps a fresh machine by
shallow-cloning the repo to `~/.mac-bootstrap/repo` and re-execing from it
(updated 2026-09-03). Selected apps are installed and kept updated on every
run; deselected apps are uninstalled. `./update.sh` pulls the repo, then
updates everything currently managed. The repo holds only automation; each
machine's selection lives in `~/.mac-bootstrap/apps.conf`, outside any
checkout or synced storage.

## Managed apps (initial set)

| App id | Display name | Method | Source |
|---|---|---|---|
| `chrome` | Google Chrome | brew cask | `google-chrome` |
| `firefox` | Firefox | brew cask | `firefox` |
| `little-snitch` | Little Snitch | brew cask | `little-snitch` |
| `controld` | Control D (GUI) | direct dmg | `https://assets.controld.com/utility/controld_{arm,x86}.dmg` by arch; installs `Control D Utility App.app` |
| `claude` | Claude Desktop | brew cask | `claude` |
| `claude-code` | Claude Code | native installer | `https://claude.ai/install.sh` → `~/.local/bin/claude` (self-updates; brew cask dropped 2026-09-03 — it trails releases) |
| `gemini` | Google Gemini Desktop | brew cask | `google-gemini` |
| `gemini-cli` | Gemini CLI | brew formula | `gemini-cli` |
| `chatgpt` | ChatGPT | brew cask | `chatgpt` |
| `maccy` | Maccy | brew cask | `maccy` |

**Grok is excluded** (decided 2026-08-28): xAI ships no official macOS
distribution — no cask, no Mac App Store app (the App Store "Grok AI" is
iOS/iPadOS-only), no dmg. Revisit if xAI releases a desktop app; adding it back
is one new `apps/grok.sh` file. README notes it as web-only.

**Added 2026-08-30:**

| App id | Display name | Method | Source |
|---|---|---|---|
| `dropbox` | Dropbox | brew cask | `dropbox` |
| `google-drive` | Google Drive | brew cask | `google-drive` |
| `claude-plugins` | Claude Code plugins | `claude plugin` CLI | 11-plugin roster from 8 marketplaces (manifest in the app script) |
| `gsd` | GSD skill suite | npm global | `get-shit-done-cc`; installs `node` formula if npm missing; installed-check is the deployed footprint (`~/.local/bin/gsd-sdk`, `~/.claude/skills/gsd-*`), not the npm tree |
| `agent-skills` | Provenance-tracked agent skills | skills.sh CLI | Roster of repo\|skill-list records in the app script (2026-08-30: 57 skills from `softaworks/agent-toolkit`, `composiohq/skills`, `coreyhaines31/marketingskills`, `lyndonkl/claude`, `alirezarezvani/claude-skills`); updates always selective by name (bare `skills update` would sync upstream deletions of the culled mattpocock skills); local-only skills are out of scope |

The agent-tooling rosters mirror `claude-nyamaste-studios-strategy/tech/skills.md`
(2026-08-27 audit) and live inside their `apps/*.sh` files as the single source
of truth.

**Added 2026-09-04** (container + mobile development):

| App id | Display name | Method | Source |
|---|---|---|---|
| `docker` | Docker Desktop | brew cask | `docker-desktop` (the deprecated `docker` cask name is not used); chosen over docker CLI + colima 2026-09-04 as the interactive/GUI engine — see `colima` below for the boot-time engine added later the same day |
| `xcode` | Xcode | Mac App Store via `mas` | `mas install 497799835`; needs App Store sign-in; install/update run license accept + `-runFirstLaunch` + `xcode-select -s` (sudo); mas cannot uninstall — removal deletes the bundle, zap also clears `~/Library/Developer` |
| `fastlane` | fastlane | brew formula | `fastlane`; the only extra iOS build tool chosen (no CocoaPods/swiftlint — SwiftPM ships in Xcode) |
| `android-studio` | Android Studio | brew cask | `android-studio`; SDK/emulators via the IDE's first-launch wizard; `.zprofile` prefers `~/Library/Android/sdk` over brew commandlinetools for `ANDROID_HOME` |

**Added 2026-09-04** (reboot-surviving containers):

| App id | Display name | Method | Source |
|---|---|---|---|
| `colima` | Colima (headless Docker engine) | brew formulas | `colima` + `docker` + `docker-compose`; a system LaunchDaemon (`/Library/LaunchDaemons/dev.colima.plist`, `RunAtLoad` + `KeepAlive`, runs as the user) starts the VM at boot before login so containers with `--restart` policies survive reboot — the one thing Docker Desktop's per-user GUI engine cannot do. Coexists with `docker` (Docker Desktop): separate engines, separate container stores; reboot-surviving containers go in the colima docker context. Requires FileVault off (a locked disk blocks everything at boot; conflicts with the hardening spec's FileVault item — resolve per machine). Not root: launchd's `UserName` key runs it as the user pre-login. If the default vz driver won't start pre-login, fall back to `--vm-type qemu` |

**Added 2026-09-04** (terminal + creative tools):

| App id | Display name | Method | Source |
|---|---|---|---|
| `iterm` | iTerm2 | brew cask | `iterm2` (self-updates) |
| `adobe-cc` | Adobe Creative Cloud | brew cask | `adobe-creative-cloud` (self-updates); installs only the CC desktop app — individual Adobe apps are installed from inside it after sign-in, and cask uninstall removes only the CC app itself |

**Added 2026-09-04** (AI coding agents):

| App id | Display name | Method | Source |
|---|---|---|---|
| `codex` | Codex CLI | brew cask | `codex` (binary release from github.com/openai/codex; no self-update, brew upgrades it) |
| `antigravity` | Google Antigravity | brew cask | `antigravity` (self-updates) |

**Added 2026-09-04** (text editor):

| App id | Display name | Method | Source |
|---|---|---|---|
| `sublime-text` | Sublime Text | brew cask | `sublime-text` (self-updates); license activation is manual (unlicensed build is fully functional with purchase reminders) |

**Categories (added 2026-09-04):** each `apps/*.sh` sets `APP_CATEGORY`
(captured by `discover_apps` alongside `APP_NAME`/`APP_NOTE`); the `run.sh`
checklist groups apps under category headers in the order AI, Browsers,
Development, Creative, Cloud Storage, System Tools, with unknown/unset
categories appended (unset falls back to "Other"). Toggle numbers remain the
discovery index, so grouping never changes an app's number.

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
```

Machine-local state lives outside the repo in `~/.mac-bootstrap/` (see below);
`local/` in the repo is only the gitignored legacy config location.

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
  user already installed manually is taken over instead of erroring. Adopt only
  accepts an identical copy, so on failure (version drift — the normal case for
  self-updating apps) it falls back to `brew install --cask --force`, replacing
  the bundle with the cask's copy; settings in `~/Library` survive.
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

- Path: `~/.mac-bootstrap/apps.conf` (updated 2026-09-03; overridable via
  `BOOTSTRAP_CONFIG_DIR`, and `MAC_BOOTSTRAP_HOME` moves the whole state dir).
- Rationale: each machine clones the repo from git and keeps its selection in
  the user's home dir — the repo never stores machine config, and the config
  survives the checkout being moved or re-cloned. The pre-2026-09-03 location
  was `local/$(hostname -s).conf` inside the repo; `load_config` migrates such
  a file automatically.
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
6. Save the new selection to `~/.mac-bootstrap/apps.conf`.
7. Print a summary: installed / updated / removed, plus post-install
   notes (e.g. Little Snitch requires manual system-extension approval in
   System Settings; App/daemon sign-ins are manual).

Idempotent throughout: re-running with an unchanged selection just updates.

## update.sh flow

1. `git pull --ff-only` the repo itself (non-fatal — offline or diverged
   checkouts run what they have).
2. Load `~/.mac-bootstrap/apps.conf`; exit with guidance if missing (run
   `run.sh` first).
3. `brew update`.
4. For each selected app: `<id>_update`. Brew upgrades touch only managed
   casks/formulas — never the machine's unrelated brew packages.
5. Supports `--dry-run`. Summary at the end.

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
