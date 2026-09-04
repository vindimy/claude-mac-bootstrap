# claude-mac-bootstrap

Bootstrap and continuously maintain a desired macOS machine configuration — apps, tools,
and their configs — managed via automation. Each machine clones this repo from git
and runs the automation locally; the repo holds only scripts, never a machine's
configuration. `install.sh` symlinks the managed files into place per machine.

## Setup on a new machine

One command, no prerequisites beyond macOS (if git's Command Line Tools are
missing it starts their installer and asks you to re-run):

```sh
curl -fsSL https://raw.githubusercontent.com/vindimy/claude-mac-bootstrap/main/run.sh | bash
```

A standalone `run.sh` shallow-clones the repo to `~/.mac-bootstrap/repo` (or
fast-forwards an existing clone) and re-execs from there. You can equally
clone the repo anywhere yourself and run `./run.sh` from the checkout — the
scripts don't care where the repo lives, and all machine-local state stays in
`~/.mac-bootstrap/`.

`run.sh` installs Homebrew if needed, links the managed dotfiles (via
`install.sh`), then installs/updates the apps you pick. Re-run it any time to
change the selection — deselected apps are uninstalled (you choose per app
whether their settings are kept or zapped).

Non-interactive use:

```sh
./run.sh --non-interactive            # reuse this machine's saved selection
./run.sh --apps chrome,maccy          # set the selection, skipping the checklist
./run.sh --non-interactive --apps none  # uninstall everything managed, no prompts (settings kept)
./run.sh --dry-run --apps chrome      # print actions without executing
./update.sh                           # pull the repo, then update Homebrew + all selected apps
```

`--apps` only replaces the checklist step — removals of deselected apps still
prompt keep-or-zap per app unless `--non-interactive` is also given, in which
case removals proceed without prompting and settings are kept.

## Managed files

| Repo file | Installed at | Purpose |
|---|---|---|
| `dotfiles/.zprofile` | `~/.zprofile` and `~/.profile` (symlinks) | Login-shell env for zsh and bash: Homebrew, PATH, Java/Android; triggers the daily dropbox-ignore-git sweep |
| `bin/dropbox-ignore-git.sh` | `~/.local/bin/dropbox-ignore-git.sh` (symlink) | Marks every `.git` dir under `~/Library/CloudStorage/Dropbox` with `com.dropbox.ignored=1` so Dropbox sync can never corrupt a git index; no-ops on machines without a Dropbox folder |

## Managed apps

Selected per machine via `run.sh`; the selection lives in
`~/.mac-bootstrap/apps.conf` — the repo holds only automation, never a
machine's configuration. (A pre-2026-09-03 `local/<hostname>.conf` inside the
repo is migrated there automatically.)

Per-app operational notes — post-install steps, gotchas, recovery — live in
[docs/howto.md](docs/howto.md).

| App id | App | How |
|---|---|---|
| `chrome` | Google Chrome | brew cask `google-chrome` (self-updates) |
| `dropbox` | Dropbox | brew cask `dropbox` (self-updates) |
| `firefox` | Firefox | brew cask `firefox` |
| `google-drive` | Google Drive | brew cask `google-drive` (self-updates) |
| `little-snitch` | Little Snitch | brew cask `little-snitch`; system-extension approval + license are manual |
| `controld` | Control D GUI utility | vendor dmg from assets.controld.com (self-updates) |
| `claude` | Claude Desktop | brew cask `claude` (self-updates) |
| `claude-code` | Claude Code | native installer `claude.ai/install.sh` (self-updates); brew cask dropped — it trails releases |
| `gemini` | Google Gemini Desktop | brew cask `google-gemini` (self-updates) |
| `gemini-cli` | Gemini CLI | brew formula `gemini-cli` |
| `chatgpt` | ChatGPT | brew cask `chatgpt` (self-updates) |
| `maccy` | Maccy | brew cask `maccy` |
| `iterm` | iTerm2 | brew cask `iterm2` (self-updates) |
| `adobe-cc` | Adobe Creative Cloud | brew cask `adobe-creative-cloud` (self-updates); sign in, then install individual Adobe apps from the CC app |
| `docker` | Docker Desktop | brew cask `docker-desktop` (self-updates); approve the privileged helper on first launch |
| `colima` | Colima (headless Docker engine) | brew formulas `colima` + `docker` + `docker-compose`; LaunchDaemon starts the VM at boot (pre-login) so `--restart` containers survive reboot; needs FileVault off; separate engine from Docker Desktop |
| `xcode` | Xcode (iOS builds) | Mac App Store via brew formula `mas`; needs App Store sign-in, accepts license + first-launch setup (sudo) |
| `fastlane` | fastlane | brew formula `fastlane`; iOS/Android build + release automation |
| `android-studio` | Android Studio | brew cask `android-studio` (self-updates); SDK via first-launch wizard, `.zprofile` exports `ANDROID_HOME` when the SDK exists |
| `claude-plugins` | Claude Code plugins (11 from 8 marketplaces) | `claude plugin` CLI; needs `claude-code` |
| `gsd` | GSD skill suite (67 `gsd-*` skills) | npm `get-shit-done-cc` (installs Node if needed) |
| `agent-skills` | Provenance-tracked agent skills (57 from 5 repos: softaworks/agent-toolkit, composio, coreyhaines31/marketingskills, lyndonkl/claude, alirezarezvani/claude-skills) | skills.sh CLI (`npx skills`), selective updates only; roster in `apps/agent-skills.sh` |
| `codex` | Codex CLI | brew cask `codex` (binary release; brew-updated) |
| `antigravity` | Google Antigravity | brew cask `antigravity` (self-updates) |

The `run.sh` checklist groups apps by category (AI, Browsers, Development,
Creative, Cloud Storage, System Tools) from each app's `APP_CATEGORY`; the
numbers stay stable across groupings.

The three agent-tooling units mirror the inventory in
`claude-nyamaste-studios-strategy/tech/skills.md`. `agent-skills` manages only
the upstream-restorable set and always updates selectively by name — never a
bare `skills update`, which would sync upstream's deletion of the culled
mattpocock skills. Local-only skills (the 20 mattpocock survivors, the 19
awesome-claude-skills copies, graphify) live solely in `~/.agents/skills` and
are synced manually, not managed here.

Grok has no official macOS app (no cask, no Mac App Store app, no dmg as of
2026-08-28) and is web-only for now. To add a new app later: drop an
`apps/<id>.sh` setting `APP_NAME` and `APP_CATEGORY` and implementing
`<id>_install/_update/_uninstall/_installed` (hyphens become underscores) —
nothing else to register. Apps without an `APP_CATEGORY` group under "Other".

`update.sh` updates Homebrew plus only the selected apps; casks marked
self-updating are left to their own updaters unless missing.

## dropbox-ignore-git sweep

- **Why:** Dropbox treats `.git` internals as ordinary files and can roll back
  `.git/index` mid-session, silently corrupting commits (bit us 2026-08-01).
- **How it runs:** triggered from `.zprofile` on login shells, throttled to once per
  24h via stamp file `~/.local/state/dropbox-ignore-git.stamp`, logging to
  `~/Library/Logs/dropbox-ignore-git.log`.
- **Why not launchd/cron:** macOS TCC blocks background jobs from reading
  `~/Library/CloudStorage`; a shell-profile trigger inherits the terminal's
  permissions instead. Do not "fix" this by moving it to a LaunchAgent.
- The `com.dropbox.ignored` xattr is per-machine — the sweep must run on each machine.
- Dropbox is optional everywhere: the sweep exits silently when
  `~/Library/CloudStorage/Dropbox` doesn't exist, so machines without Dropbox
  pay nothing.

## History

`dotfiles/.zprofile` and `bin/dropbox-ignore-git.sh` were adopted into the
repo 2026-08-28 from unmanaged per-machine copies. The per-machine app
selection moved from the repo-local `local/<hostname>.conf` to
`~/.mac-bootstrap/apps.conf` on 2026-09-03, when `run.sh` also became
curl-able (standalone shallow-clone bootstrap).
