# claude-mac-bootstrap

Bootstrap and continuously maintain a desired macOS machine configuration — apps, tools,
and their configs — managed via automation. The repo lives in Dropbox
(`~/Dropbox/Dev/claude-mac-bootstrap`) so every machine syncs it; `install.sh` symlinks
the managed files into place per machine.

## Setup on a new machine

1. Install Dropbox and let `Dev/claude-mac-bootstrap` sync.
2. Run `~/Dropbox/Dev/claude-mac-bootstrap/install.sh` from a terminal.

`install.sh` is idempotent — re-run it any time (e.g. after new files are added here).
It backs up any pre-existing real file as `<file>.pre-bootstrap.bak` before linking.

## Managed files

| Repo file | Installed at | Purpose |
|---|---|---|
| `dotfiles/.zprofile` | `~/.zprofile` (symlink) | Login-shell env: Homebrew, PATH, Java/Android; triggers the daily dropbox-ignore-git sweep |
| `bin/dropbox-ignore-git.sh` | `~/.local/bin/dropbox-ignore-git.sh` (symlink) | Marks every `.git` dir under `~/Library/CloudStorage/Dropbox` with `com.dropbox.ignored=1` so Dropbox sync can never corrupt a git index |

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
