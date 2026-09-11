# How-to: operating the managed apps

Operational knowledge that is not obvious from the app units themselves —
post-install steps, per-machine gotchas, and recovery procedures. One section
per app (apps with nothing beyond "it installs" are omitted).

## Table of contents

- [General: running the bootstrap](#general-running-the-bootstrap)
- [colima](#colima)
- [docker (Docker Desktop)](#docker-docker-desktop)
- [claude-code](#claude-code)
- [claude-plugins](#claude-plugins)
- [agent-skills / agent-skill-suites](#agent-skills--agent-skill-suites)
- [gsd](#gsd)
- [mcp-servers](#mcp-servers)
- [dropbox](#dropbox)
- [controld](#controld)
- [little-snitch](#little-snitch)
- [xcode](#xcode)
- [android-studio](#android-studio)
- [vscode](#vscode)
- [adobe-cc](#adobe-cc)
- [hardening](#hardening)
- [performance](#performance)
- [telegram](#telegram)
- [amneziavpn](#amneziavpn)

## General: running the bootstrap

- `./run.sh` is idempotent — re-run it any time; already-installed apps are
  skipped, failed or newly selected ones are installed.
- Per-machine app selection lives in `~/.mac-bootstrap/apps.conf` (outside the
  repo, machine-local by design).
- `DRY_RUN=1 ./run.sh` prints every mutating command instead of running it.
- If a cask uninstall fails with "It seems there is already an App at
  '/opt/homebrew/Caskroom/...'", an earlier uninstall was interrupted after
  Homebrew copied the app back into the Caskroom. `run.sh` offers to retry
  with `brew uninstall --cask --force`, which overwrites that leftover copy;
  the retry only runs after you confirm, never under `--non-interactive`.
- On a fresh machine the Xcode CLT GUI installer window can open **behind**
  the Terminal window — move Terminal if the install seems stalled.

## colima

Headless Docker engine whose VM starts **at boot, before login**, via the
LaunchDaemon `/Library/LaunchDaemons/dev.colima.plist`. Docker Desktop cannot
do this (per-user GUI app); colima is the engine for containers that must
survive reboot.

**Making containers survive reboot** — both parts are required:

1. Run them in the colima context: `docker context use colima`.
2. Give them a restart policy: `docker run -d --restart unless-stopped ...`
   (or `--restart always`). Containers without a restart policy stay down
   after reboot by design.

**One-time validation after install** (do this once per machine):

1. `sudo reboot` and do **not** log in.
2. From another machine, confirm the container answers (or SSH in and run
   `docker ps` in the colima context).
3. If it didn't come up: log in and check `/tmp/colima.launchd.log`. If the
   default vz driver won't start pre-login, recreate the VM on the
   daemon-safe QEMU driver: `colima delete && colima start --vm-type qemu`.

**Stopping the engine for real:** `colima stop` alone is not enough — the
daemon's `KeepAlive` restarts it. Unload the daemon first:

```sh
sudo launchctl bootout system/dev.colima          # stop + disable
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.colima.plist  # re-enable
```

**Using existing docker-compose workflows:** compose follows the active
docker context, so existing projects work unchanged:

1. `docker context use colima` (once — it sticks until something switches it;
   Docker Desktop may steal it back to `desktop-linux` when it starts).
2. In the project directory, `docker compose up -d` as usual. The unit
   installs the brew `docker-compose` formula; if the plugin form
   (`docker compose`) is not recognized, either call the standalone
   `docker-compose` binary or add brew's plugin dir to `~/.docker/config.json`:
   `{"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]}`.
3. For reboot survival, give every service a restart policy in the compose
   file (`restart: unless-stopped`) — after a reboot dockerd restarts the
   containers itself; there is no need to re-run `docker compose up`.
4. For tools that ignore docker contexts, point them at the socket directly:
   `DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`.

**Requirements and gotchas:**

- FileVault must stay **off** on the machine — a locked disk blocks
  everything at boot. This deliberately conflicts with the hardening spec's
  FileVault item; resolve per machine.
- Colima and Docker Desktop are separate engines with **separate container
  stores**. A container is in one or the other; the Docker Desktop dashboard
  never shows colima's containers.
- Useful commands: `colima status`, `docker context ls`,
  `colima ssh` (shell inside the VM).

## docker (Docker Desktop)

- Open Docker.app once after install: the first launch asks to approve a
  privileged helper and finishes setup.
- Its engine runs only while you are logged in — containers here do **not**
  survive an unattended reboot. Use [colima](#colima) for those; keep Docker
  Desktop for interactive/GUI work.
- Docker Desktop may switch the active docker context to `desktop-linux` when
  it starts. Check with `docker context ls`, switch back with
  `docker context use colima`.

## claude-code

- Installed by the native installer to `~/.local/bin/claude` (the brew cask
  is deliberately not used — it trails releases). The app keeps itself
  current.
- If `claude` is not found in a fresh shell, `~/.local/bin` is missing from
  PATH — the managed `.zprofile` adds it at next login.
- `~/.claude/settings.json` is managed: the unit copies
  `dotfiles/.claude/settings.json` over it on install and on every
  `update.sh` run whenever the two differ. To change a global setting, edit
  the repo file and commit — anything changed in the live file (by hand or
  by Claude Code via `/model`, `/theme`, `/plugin`, `claude plugin install`)
  is discarded at the next run. The first differing live file is kept once
  as `~/.claude/settings.json.pre-bootstrap.bak`.
- `~/.claude/statusline-command.sh` is managed the same way (copied from
  `dotfiles/.claude/statusline-command.sh` whenever it differs). It is what
  `statusLine.command` in settings.json runs; edit the repo copy to change
  the status line's fields or colors. It needs `jq`, which macOS ships.
- The `claude-plugins` unit re-applies the settings after installing
  plugins, because `claude plugin install` marks each plugin enabled and the
  managed profile keeps part of the roster installed-but-disabled.
- `--dry-run` prints the copy without touching the live file.
- To see what the lean profile actually buys, run `claude-context-audit.sh`
  (installed by `install.sh`). It needs `node` on PATH and one API request;
  results and the full request dump land under
  `~/.local/state/claude-context-audit/`. If it reports input tokens up 10%+
  since the last run, find the new tool in its ranked table and add it to
  `permissions.deny` (bare name — a scoped rule like `Bash(rm *)` blocks the
  call but keeps the schema in the payload) or turn the feature off with a
  `disable*` flag; for a skill, set it to `user-invocable-only` in
  `skillOverrides`. Restart Claude Code and re-run the audit to confirm.
- Port 8787 busy? The script walks up to the next free port. A stuck proxy
  from an interrupted run: `lsof -nP -iTCP:8787` and kill it.

## claude-plugins

- Requires the `claude-code` app; plugins install headlessly via
  `claude plugin`.
- Restart Claude Code (new session) after installing or updating plugins —
  a running session does not pick them up.

## agent-skills / agent-skill-suites

- Both units install through the skills.sh CLI (`npx -y skills`) into the
  shared store `~/.agents/skills`, linked into every detected agent
  (`~/.claude/skills`, `~/.codex/skills`, `~/.gemini/skills` — Gemini CLI
  reads it natively, `gemini skills list` shows what it sees). Node is
  installed first if `npx` is missing.
- **Choosing skills.** First install in an interactive `./run.sh` shows a
  checklist per repo: toggle numbers, `a` = all, `n` = none, Enter confirms.
  Checking every skill saves `*` ("track all": new upstream skills arrive on
  the next update, removed ones are cleaned out). Anything else saves an
  explicit list that only changes when you reselect. Non-interactive first
  installs take the roster defaults.
- **Reselecting.** Later interactive `./run.sh` passes ask
  `Reselect skills for <unit>? [y/N]` once per unit; Enter skips. Skills new
  upstream since your last explicit selection are tagged `(new)`.
  `./update.sh` never prompts.
- **Where it is saved.** `~/.mac-bootstrap/skills.conf`, one `SKILLS_<repo>`
  line per repo. Editing it by hand and running `./update.sh` is a valid way
  to change a selection on a headless machine.
- **superpowers** is installed for Codex only (`-a codex`): Claude Code keeps
  the `superpowers` plugin (its SessionStart hook is what makes it fire), and
  a link under `~/.claude/skills` would list every skill twice. Codex reads
  the shared store `~/.agents/skills` directly, so the CLI creates no links
  for it — `~/.codex/skills` staying empty is expected. If `~/.codex` or
  `~/.gemini` does not exist yet (the agent not installed), the repo is
  skipped for that agent and installed on the next update.
- **mattpocock-skills plugin.** Replaced by the suites unit on 2026-09-08
  (the plugin was skills-only). On a machine that still has it:
  `claude plugin uninstall mattpocock-skills@claude-plugins-official`.
- Removing a unit removes only the skills the lock file attributes to its
  repos; `zap` also forgets its `skills.conf` lines. Skills from other
  sources are never touched, and the units never run a bare `skills update`.
- The CLI takes space-separated names after `-s` and `-a`, not a comma list.
- A roster agents field of `*` is resolved to the installed agents the units
  know (`claude-code`, `codex`; see `SKILLS_KNOWN_AGENTS` in `lib/skills.sh`)
  and passed as an explicit `-a`. Letting the CLI pick agents itself
  (`add -g -y` with no `-a`) adds every `.agents/skills` agent including
  PromptScript, which has no global dir, so each run ended with a red
  "Failed to install N ... PromptScript does not support global skill
  installation" block. Harmless (exit 0, skills installed), but noise —
  upstream bug vercel-labs/skills#1424, open since 2026-06.

## gsd

- For future updates prefer running the `gsd-update` skill inside Claude
  Code — it backs up custom files before GSD's clean-install step.

## mcp-servers

- **What it does.** Applies `dotfiles/mcp-servers.conf` to every installed
  agent CLI in user scope: `claude mcp add -s user`, `codex mcp add`,
  `gemini mcp add -s user`. Agents not installed yet are skipped and picked
  up on the next `./update.sh`. What was applied is recorded per machine in
  `~/.mac-bootstrap/mcp.conf`; only servers in that file are ever removed, so
  anything you add yourself with the CLIs is left alone.
- **Adding a server.** One line, `name|stdio|command args...` or
  `name|http|url`; a leading `~/` is expanded. Commit, then `./update.sh`.
  Editing a line re-applies it (remove + add); deleting a line removes the
  server from every agent. Verify with `claude mcp list`, `codex mcp list`,
  `gemini mcp list`.
- **github.** `bin/github-mcp.sh` (linked into `~/.local/bin`) runs the
  `github-mcp-server` formula with the token from `gh auth token`; run
  `gh auth login` once. Toolsets are limited to `repos,issues,pull_requests`
  — edit the `--toolsets` list in the script to widen.
- **Context cost.** Every server's tools ride along in Claude Code's per-turn
  payload. Run `claude-context-audit.sh` after a roster change; trim
  individual tools with bare `mcp__<server>__<tool>` names in
  `permissions.deny` in `dotfiles/.claude/settings.json`.
- **Name clash.** If an agent already has a server with a roster name that
  this unit did not add, the unit logs it and leaves it alone. `claude mcp
  get` and `codex mcp get` see every scope, so a same-named server in a
  project or local scope of the directory `run.sh` runs from also counts as
  a clash; remove it or rename it to let the unit manage the user-scope
  copy.

## dropbox

- If install fails, enable the extension in System Settings → Privacy &
  Security and retry.
- Open Dropbox and sign in to start syncing. Per-machine sync selections
  (selective sync) are manual and machine-local.
- The repo itself is distributed by `git clone`, not Dropbox sync — never
  depend on Dropbox for repo state on a new machine.
- `.git` dirs and build/dependency dirs (`node_modules`, `.wrangler`, `.venv`,
  `Pods`, Gradle/Xcode output, …) under the Dropbox folder are excluded from
  sync by the daily `dropbox-ignore-git` sweep (see README). To apply it right
  away, e.g. after cloning a project or `npm install`, run
  `~/.local/bin/dropbox-ignore-git.sh`; it prints only the dirs it newly
  flagged. A flagged dir stays on this machine but is removed from
  dropbox.com and other devices, so `npm install` there as usual.

## controld

- Open "Control D Utility App" and sign in to finish DNS setup. Resolver
  config is per-machine and not managed by this repo.

## little-snitch

- System-extension approval (System Settings → Privacy & Security) and the
  license are manual.

## xcode

- Needs App Store sign-in before `mas` can install it.
- Install/update run license accept + `-runFirstLaunch` + `xcode-select -s`
  (sudo prompts are expected).
- `mas` cannot uninstall — removal deletes the app bundle; zap also clears
  `~/Library/Developer`.

## android-studio

- The SDK and emulators come from the IDE's first-launch wizard, not brew.
- The managed `.zprofile` exports `ANDROID_HOME` preferring
  `~/Library/Android/sdk` once the SDK exists.

## vscode

- **Agent extensions.** Installed by the unit for whichever agent CLIs are
  installed: `claude-code` → anthropic.claude-code, `codex` → openai.chatgpt,
  `gemini-cli` → Gemini CLI Companion. Each extension
  signs in on first use (Anthropic, ChatGPT and Google accounts
  respectively). Skills and MCP servers need nothing extra — the extensions
  run the same CLIs against the same home directories.
- **Where they appear.** Claude Code and Codex register a view in the
  secondary (right) side bar, so they show as tabs there. Gemini CLI
  Companion contributes no panel at all, only commands such as `Gemini CLI:
  Run`, which opens Gemini CLI in a terminal with editor context. A missing
  Gemini tab on the right is therefore expected, not a failed install.
- **Gemini Code Assist is not installed.** Its VS Code client
  (google.geminicodeassist) stopped serving individual Google accounts in
  September 2026 — it answers sign-in with "no longer supported for Gemini
  Code Assist for individuals" and points at Antigravity — so only enterprise
  sign-ins would get anything from it. The unit no longer installs it. If an
  earlier run left it behind, remove it with
  `code --uninstall-extension google.geminicodeassist`.
- **Ordering.** On a first run that also installs the agent CLIs, `vscode`
  is applied after the agent CLIs (units load alphabetically and `vscode`
  sorts after them), so the extensions land on the same run. If an agent is
  added later, its extension follows on the next `./run.sh` / `./update.sh`.
- **Removal.** Deselecting an agent CLI leaves its extension in VS Code
  (uninstall it from the Extensions view). Deselecting `vscode` with zap
  removes `~/.vscode` and the app's user settings along with the app.

## adobe-cc

- The cask installs only the Creative Cloud desktop app. Sign in, then
  install individual Adobe apps from inside it. Uninstalling the cask removes
  only the CC app itself.

## hardening

A settings unit, not an app: selecting it applies a security baseline, every
`update.sh` run re-applies it (drift correction), and deselecting with `zap`
restores macOS defaults. Every run asks for your admin password once.
Design and rationale: `docs/superpowers/specs/2026-09-04-macos-hardening-design.md`.

**What it changes:** application firewall on with stealth mode;
guest login and SMB guest access off; automatic login removed; automatic
updates set to security-only — check, download, security responses and system
data files on, App Store app updates on, but **macOS updates are not installed
automatically** (they download and wait for you in System Settings > General >
Software Update); all filename extensions shown in Finder; Touch ID accepted
by `sudo`.

**What it only reports** (warnings, never changed for you):

- FileVault off → System Settings > Privacy & Security > FileVault. Save the
  recovery key. Skip this on a machine that runs colima at boot — that needs
  FileVault off.
- SIP disabled → boot to Recovery, run `csrutil enable`.
- Gatekeeper off → System Settings > Privacy & Security; `spctl` can no
  longer turn it back on since Sequoia.
- SSH accepts passwords while Remote Login is on. Remote Login itself is left
  alone. To go key-only, first confirm your key works, then:

  ```sh
  sudo tee /etc/ssh/sshd_config.d/010-keys-only.conf >/dev/null <<'EOF'
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  EOF
  sudo launchctl kickstart -k system/com.openssh.sshd
  ```

**Touch ID for sudo** is one line in `/etc/pam.d/sudo_local`, which survives
OS updates. The unit appends, never overwrites, so a hand-added `pam_reattach`
line (for tmux) stays and keeps its place ahead of `pam_tid`. On a Mac without
Touch ID the line is harmless — sudo falls through to the password prompt.

**Verify after applying:**

```sh
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --getstealthmode
defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled          # 0
defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall              # 1
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates  # 0
cat /etc/pam.d/sudo_local
```

Finder needs a relaunch (`killall Finder`) to show extensions everywhere.

## performance

A settings unit like `hardening`: applied on selection, re-applied on every
update, `zap` restores defaults. Needs sudo. Some changes (Siri, Handoff,
Apple Intelligence) fully take effect after logout or restart.

**What it changes:**

- Power: on AC the Mac never sleeps, disks never sleep, Power Nap is off. On
  battery only disk sleep is turned off; everything else stays default. This
  is what keeps the Mac mini up for colima and SSH without touching the
  MacBook Air's battery life. `disksleep 0` only stops macOS from spinning
  drives down — a drive whose own firmware has an idle timer still sleeps and
  needs the vendor's tool (e.g. Seagate/WD dashboard).
- Spotlight: indexing off on every mounted external volume. Re-run
  `./update.sh` after attaching a new drive to cover it. To also drop an
  existing index and reclaim the space on a drive: `sudo mdutil -E /Volumes/<name>`
  (with indexing already off this erases without rebuilding).
- Off: Siri (agent + menu item), Apple Intelligence (macOS 15+; nothing to do
  on Sonoma), Photos and media analysis agents (`photoanalysisd`,
  `mediaanalysisd` — Photos face/scene search stops working), Handoff, crash
  report dialogs, and analytics upload to Apple.

**Manual steps it prints every run:**

- Spotlight indexes `~/Library/Caches` (tens of thousands of items on a dev
  machine). The privacy list is not scriptable without disabling SIP, so once
  per machine: System Settings > Siri & Spotlight > Spotlight Privacy…
  (Search Privacy… on macOS 15+) > `+` > press Cmd-Shift-G and enter
  `~/Library/Caches` > Open > Done.
- Siri Suggestions in Spotlight: System Settings > Siri & Spotlight >
  Spotlight > uncheck "Siri Suggestions".

**TRIM** is reported per SSD, never forced. Internal SSDs and Thunderbolt /
USB4 NVMe enclosures negotiate TRIM automatically under APFS. Plain USB
enclosures never get TRIM on macOS and `trimforce` does not change that (it
only affects SATA third-party SSDs). If an external SSD shows `TRIM Support:
No`, the fix is a Thunderbolt/USB4 enclosure, not a command.

**Verify after applying:**

```sh
pmset -g custom                                  # AC Power: sleep 0, disksleep 0, powernap 0
mdutil -s -a                                     # externals: Indexing disabled
launchctl print-disabled gui/$(id -u) | grep -E 'Siri.agent|photoanalysisd|mediaanalysisd'
defaults read com.apple.assistant.support 'Assistant Enabled'   # 0
```

**Reverting** (`run.sh`, deselect, choose `zap`) restores the recorded Apple
silicon power defaults (`sleep 1 disksleep 10 powernap 1`; `disksleep 10` on
battery), turns indexing back on for external volumes, re-enables the three
agents and Siri, and deletes the remaining managed keys.

## telegram

- The unit installs the `telegram-desktop` cask (tdesktop build, bundle id
  `com.tdesktop.Telegram`), which lands as `/Applications/Telegram Desktop.app`.
  The `telegram` cask is a different app (the native Swift "Telegram for
  macOS") and is intentionally not used.
- A Telegram Desktop that was installed by hand lives at
  `/Applications/Telegram.app`, so `brew --adopt` does not match it and you end
  up with two copies. After the first managed install, quit the old one and
  remove it (and any stray `/Applications/Telegram.localized` folder). Chats
  and login carry over — they live in `~/Library/Application Support/Telegram Desktop`.

## amneziavpn

- The Homebrew cask is an Intel-only pkg. On Apple silicon the installer
  refuses with "This package requires Rosetta 2 to be installed", so the unit
  installs Rosetta 2 first via `sudo softwareupdate --install-rosetta`
  (a second admin-password prompt, before the pkg's own).
- If that step fails, install Rosetta by hand with the same command and
  re-run `./run.sh`.
