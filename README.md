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
| `bin/claude-context-audit.sh` | `~/.local/bin/claude-context-audit.sh` (symlink) | Measures the hidden per-turn payload Claude Code sends the model (tool schemas, skills catalogue, system prompt) through a local logging proxy and keeps a history so growth is visible; see [Claude Code context audit](#claude-code-context-audit) |
| `bin/agent-proxy.mjs` | `~/.local/state/claude-context-audit/agent-proxy/proxy.mjs` (copy, refreshed by the audit script whenever it differs) | Matt Pocock's zero-dependency logging proxy, vendored at gist revision `e142f08f` (provenance in its header). Runs from the state dir so its `logs/` land there, never in the checkout |
| `dotfiles/.claude/settings.json` | `~/.claude/settings.json` (copy, written by the `claude-code` unit on every install/update) | Global Claude Code settings: enabled plugins, tool deny list, skill visibility, feature flags. Lean profile from the 2026-09-05 system-prompt trim. The repo copy is authoritative: local edits (including ones Claude Code makes itself) are overwritten on the next run, so change the repo file instead. A copy rather than a symlink because Claude Code rewrites the file; `~/.claude` otherwise stays per-machine and is git-ignored apart from this file |
| `dotfiles/.claude/statusline-command.sh` | `~/.claude/statusline-command.sh` (copy, written by the `claude-code` unit on every install/update) | Status line script that `settings.json` points at (`statusLine.command`): repo name, git branch, context-usage bar, model. Needs `jq` (ships with macOS 15+). Repo copy is authoritative, same as `settings.json` |

## Managed apps

Selected per machine via `run.sh`; the selection lives in
`~/.mac-bootstrap/apps.conf` — the repo holds only automation, never a
machine's configuration. (A pre-2026-09-03 `local/<hostname>.conf` inside the
repo is migrated there automatically.)

Per-app operational notes — post-install steps, gotchas, recovery — live in
[docs/howto.md](docs/howto.md).

| App id | App | How |
|---|---|---|
| `chrome` | Google Chrome | vendor dmg from dl.google.com (self-updates); brew cask dropped |
| `dropbox` | Dropbox | brew cask `dropbox` (self-updates) |
| `firefox` | Firefox | vendor dmg from download.mozilla.org (self-updates); brew cask dropped |
| `google-drive` | Google Drive | brew cask `google-drive` (self-updates) |
| `little-snitch` | Little Snitch | brew cask `little-snitch`; system-extension approval + license are manual |
| `controld` | Control D GUI utility | vendor dmg from assets.controld.com (self-updates) |
| `claude` | Claude Desktop | brew cask `claude` (self-updates) |
| `claude-code` | Claude Code | native installer `claude.ai/install.sh` (self-updates); brew cask dropped — it trails releases; also copies `dotfiles/.claude/settings.json` and `dotfiles/.claude/statusline-command.sh` into `~/.claude/` (repo wins; re-applied on every update) |
| `gemini` | Google Gemini Desktop | brew cask `google-gemini` (self-updates) |
| `gemini-cli` | Gemini CLI | brew formula `gemini-cli` |
| `gh` | GitHub CLI | brew formula `gh`; run `gh auth login` once — the issue tracker convention in `docs/agents/issue-tracker.md` depends on it |
| `chatgpt` | ChatGPT | brew cask `chatgpt` (self-updates) |
| `maccy` | Maccy | brew cask `maccy` |
| `iterm` | iTerm2 | brew cask `iterm2` (self-updates) |
| `adobe-cc` | Adobe Creative Cloud | brew cask `adobe-creative-cloud` (self-updates); sign in, then install individual Adobe apps from the CC app |
| `docker` | Docker Desktop | brew cask `docker-desktop` (self-updates); approve the privileged helper on first launch |
| `colima` | Colima (headless Docker engine) | brew formulas `colima` + `docker` + `docker-compose`; LaunchDaemon starts the VM at boot (pre-login) so `--restart` containers survive reboot; needs FileVault off; separate engine from Docker Desktop |
| `xcode` | Xcode (iOS builds) | Mac App Store via brew formula `mas`; needs App Store sign-in, accepts license + first-launch setup (sudo) |
| `fastlane` | fastlane | brew formula `fastlane`; iOS/Android build + release automation |
| `android-studio` | Android Studio | brew cask `android-studio` (self-updates); SDK via first-launch wizard, `.zprofile` exports `ANDROID_HOME` when the SDK exists |
| `claude-plugins` | Claude Code plugins (11 from 9 marketplaces) | `claude plugin` CLI; needs `claude-code` |
| `gsd` | GSD skill suite (67 `gsd-*` skills) | npm `get-shit-done-cc` (installs Node if needed) |
| `agent-skills` | Agent skills, curated task packs (6 repos: softaworks/agent-toolkit, composio, coreyhaines31/marketingskills, lyndonkl/claude, alirezarezvani/claude-skills, ComposioHQ/awesome-claude-skills) | skills.sh CLI (`npx skills`); per-repo checklist on first install, saved in `~/.mac-bootstrap/skills.conf`; roster in `apps/agent-skills.sh` |
| `agent-skill-suites` | Agent skill suites (obra/superpowers for Codex only — no Claude Code duplicate, mattpocock/skills, open-gsd/gsd-pi, NeoLabHQ/context-engineering-kit) | skills.sh CLI; same checklist/selection model; `*` selections track upstream additions and removals; roster in `apps/agent-skill-suites.sh` |
| `codex` | Codex CLI | brew cask `codex` (binary release; brew-updated) |
| `antigravity` | Google Antigravity | brew cask `antigravity` (self-updates) |
| `sublime-text` | Sublime Text | brew cask `sublime-text` (self-updates) |
| `markviewer` | MarkViewer (markdown viewer) | brew cask `markviewer` (self-updates) |
| `amneziavpn` | Amnezia VPN | brew cask `amneziavpn` (pkg installer; prompts for admin password) |
| `whatsapp` | WhatsApp | brew cask `whatsapp` (self-updates) |
| `telegram` | Telegram Desktop | brew cask `telegram-desktop` (self-updates); not the `telegram` cask (native Swift build) — see [docs/howto.md](docs/howto.md#telegram) |
| `vlc` | VLC media player | brew cask `vlc` (self-updates) |
| `handbrake` | HandBrake (video transcoder) | brew cask `handbrake-app` (self-updates); not the `handbrake` formula (HandBrakeCLI) |
| `ffmpeg` | FFmpeg | brew formula `ffmpeg`; CLI converter, also used by yt-dlp to merge streams |
| `yt-dlp` | yt-dlp | brew formula `yt-dlp`; video/audio downloader driven by the `youtube-downloader` agent skill; select `ffmpeg` with it |
| `hardening` | macOS Hardening (settings, not an app) | `socketfilterfw`, `defaults`, `/etc/pam.d/sudo_local` via sudo: app firewall + stealth, guest/auto-login off, automatic security updates on (macOS upgrades stay manual), show all extensions, Touch ID for sudo; reports FileVault/SIP/Gatekeeper/SSH-password-auth; re-applied on every update; `zap` restores defaults |
| `performance` | macOS Performance Tuning (settings, not an app) | `pmset`, `mdutil`, `launchctl`, `defaults` via sudo: never sleep on AC, disks never sleep, Power Nap off, Spotlight off on external volumes, Siri + Apple Intelligence (15+) + Photos analysis + Handoff + crash/analytics reporting off; reports TRIM and manual Spotlight steps; `zap` restores defaults |

The `run.sh` checklist groups apps by category (AI, Browsers, Development,
Creative, Media, Cloud Storage, System Tools, VPN, Messaging) from each app's `APP_CATEGORY`; the
numbers stay stable across groupings.

The agent-tooling units (`claude-plugins`, `gsd`, `agent-skills`,
`agent-skill-suites`) mirror the inventory in
`claude-nyamaste-studios-strategy/tech/skills.md`. Both skills units are
rosters over the skills.sh CLI: on first install `run.sh` shows one checklist
per upstream repo (pre-checked with the roster defaults), saves the choice per
machine in `~/.mac-bootstrap/skills.conf`, and reconciles the shared store
`~/.agents/skills` against it — selected skills are (re)installed by name,
deselected ones removed, using the CLI's own lock file as the record of what
came from where. Later `run.sh` passes ask once per unit whether to reselect
(Enter = no); `update.sh` never prompts. Checking every skill of a repo saves
`*`, which also picks up skills the repo adds later. Nothing in the store is
hand-copied any more: the old local-only sets were either reinstalled from
their upstreams or removed (see the 2026-09-08 spec).

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

## Claude Code context audit

- **Why:** every Claude Code turn ships tool definitions, a skills catalogue and
  feature instructions you never see and pay for every time. The lean profile in
  `dotfiles/.claude/settings.json` trims it (bare-name `permissions.deny`,
  `disable*` flags, `skillOverrides`), but Claude Code releases, plugins and
  skills add it back. Measuring on a cadence is the only way to notice.
- **How:** `claude-context-audit.sh` copies the vendored
  [agent-proxy](https://gist.github.com/mattpocock/5b3d76ea21f5f698aefded47a9cea3b1)
  (`bin/agent-proxy.mjs`) into the state dir, starts it on a local port, sends one headless `claude -p` probe through it from an empty directory
  (global config only — no project CLAUDE.md or MCP servers), and records the
  proxy's ranked summary (tool count, tool bytes, real input tokens) in
  `~/.local/state/claude-context-audit/history.tsv`. It prints the top tools, the
  delta against the previous run (warns at +10%), and the path to the full
  request dump (system prompt + every tool schema as Markdown) under
  `~/.local/state/claude-context-audit/agent-proxy/logs/`.
  `--interactive` opens a normal session through the proxy instead;
  `--here` probes the current project; `--dry-run` prints the plan.
- **Cadence:** the script is never run unattended (one probe = one API request
  of your usual per-turn size). Instead `.zprofile`, `run.sh` and `update.sh`
  print a one-line reminder when the last run is 30+ days old or missing
  (`claude-context-audit.sh --due`). Run it after each Claude Code upgrade or
  plugin/skill change, and act on growth by editing the repo's
  `dotfiles/.claude/settings.json`. The per-session glance is the managed
  status line's context bar. Bare MCP tool names in `permissions.deny`
  (`mcp__<server>__<tool>`) strip those definitions too — the 2026-09-08 trim
  dropped context-mode's seven rarely used tools that way (21 → 13 tools,
  input tokens −15%). Method and rationale:
  [aihero.dev, "How To Kill The Bloat In Claude Code's System Prompt"](https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt).

## History

`dotfiles/.zprofile` and `bin/dropbox-ignore-git.sh` were adopted into the
repo 2026-08-28 from unmanaged per-machine copies. The per-machine app
selection moved from the repo-local `local/<hostname>.conf` to
`~/.mac-bootstrap/apps.conf` on 2026-09-03, when `run.sh` also became
curl-able (standalone shallow-clone bootstrap).
