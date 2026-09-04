# claude-mac-bootstrap

Bootstrap and continuously maintain a desired macOS machine configuration — apps, tools,
and their configs — managed via automation. Each machine clones this repo from git
and runs the automation locally; the repo holds only scripts, never a machine's
configuration. `install.sh` symlinks the managed files into place per machine.

## Setup on a new machine

1. Clone the repo:
   `git clone https://github.com/vindimy/claude-mac-bootstrap.git && cd claude-mac-bootstrap`
2. Run `./run.sh` and pick the apps this machine should manage.

`run.sh` installs Homebrew if needed, links the managed dotfiles (via
`install.sh`), then installs/updates the selected apps. Re-run it any time to
change the selection — deselected apps are uninstalled (you choose per app
whether their settings are kept or zapped).

Non-interactive use:

```sh
./run.sh --non-interactive            # reuse this machine's saved selection
./run.sh --apps chrome,maccy          # set the selection, skipping the checklist
./run.sh --non-interactive --apps none  # uninstall everything managed, no prompts (settings kept)
./run.sh --dry-run --apps chrome      # print actions without executing
./update.sh                           # update Homebrew + all selected apps
```

`--apps` only replaces the checklist step — removals of deselected apps still
prompt keep-or-zap per app unless `--non-interactive` is also given, in which
case removals proceed without prompting and settings are kept.

## Managed files

| Repo file | Installed at | Purpose |
|---|---|---|
| `dotfiles/.zprofile` | `~/.zprofile` (symlink) | Login-shell env: Homebrew, PATH, Java/Android; triggers the daily dropbox-ignore-git sweep |
| `bin/dropbox-ignore-git.sh` | `~/.local/bin/dropbox-ignore-git.sh` (symlink) | Marks every `.git` dir under `~/Library/CloudStorage/Dropbox` with `com.dropbox.ignored=1` so Dropbox sync can never corrupt a git index |

## Managed apps

Selected per machine via `run.sh`; the selection lives in
`local/<hostname>.conf` (gitignored — the repo holds only automation, never a
machine's configuration; hostname keying also keeps selections separate even
if a clone ends up in synced or shared storage).

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
| `claude-plugins` | Claude Code plugins (11 from 8 marketplaces) | `claude plugin` CLI; needs `claude-code` |
| `gsd` | GSD skill suite (67 `gsd-*` skills) | npm `get-shit-done-cc` (installs Node if needed) |
| `agent-skills` | Provenance-tracked agent skills (57 from 5 repos: softaworks/agent-toolkit, composio, coreyhaines31/marketingskills, lyndonkl/claude, alirezarezvani/claude-skills) | skills.sh CLI (`npx skills`), selective updates only; roster in `apps/agent-skills.sh` |

The three agent-tooling units mirror the inventory in
`claude-nyamaste-studios-strategy/tech/skills.md`. `agent-skills` manages only
the upstream-restorable set and always updates selectively by name — never a
bare `skills update`, which would sync upstream's deletion of the culled
mattpocock skills. Local-only skills (the 20 mattpocock survivors, the 19
awesome-claude-skills copies, graphify) live solely in `~/.agents/skills` and
are synced manually, not managed here.

Grok has no official macOS app (no cask, no Mac App Store app, no dmg as of
2026-08-28) and is web-only for now. To add a new app later: drop an
`apps/<id>.sh` implementing `<id>_install/_update/_uninstall/_installed`
(hyphens become underscores) — nothing else to register.

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

## History

`dotfiles/.zprofile` moved here 2026-08-28 from `~/Dropbox/Dev/_dotfiles/.zprofile`,
which remains as a thin stub sourcing this repo's copy (for machines whose
`~/.zprofile` symlink still points at `_dotfiles`). `bin/dropbox-ignore-git.sh` moved
here from a per-machine copy in `~/.local/bin` (created 2026-08-01).
