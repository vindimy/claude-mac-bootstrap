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
- [agent-skills](#agent-skills)
- [gsd](#gsd)
- [dropbox](#dropbox)
- [controld](#controld)
- [little-snitch](#little-snitch)
- [xcode](#xcode)
- [android-studio](#android-studio)
- [adobe-cc](#adobe-cc)
- [hardening](#hardening)
- [performance](#performance)

## General: running the bootstrap

- `./run.sh` is idempotent — re-run it any time; already-installed apps are
  skipped, failed or newly selected ones are installed.
- Per-machine app selection lives in `~/.mac-bootstrap/apps.conf` (outside the
  repo, machine-local by design).
- `DRY_RUN=1 ./run.sh` prints every mutating command instead of running it.
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

## claude-plugins

- Requires the `claude-code` app; plugins install headlessly via
  `claude plugin`.
- Restart Claude Code (new session) after installing or updating plugins —
  a running session does not pick them up.

## agent-skills

- **Never run a bare `npx skills update`.** Updates must stay selective by
  name (the unit does this): upstream culled the mattpocock skills, and a
  bulk update would sync the deletions and destroy the only surviving local
  copies.
- Local-only skills (the 20 mattpocock survivors, the 19
  awesome-claude-skills copies, graphify) live solely in `~/.agents/skills`
  and are synced manually — the unit never touches them.
- The skills CLI takes space-separated names after `-s`, not a comma list.

## gsd

- For future updates prefer running the `gsd-update` skill inside Claude
  Code — it backs up custom files before GSD's clean-install step.

## dropbox

- If install fails, enable the extension in System Settings → Privacy &
  Security and retry.
- Open Dropbox and sign in to start syncing. Per-machine sync selections
  (selective sync) are manual and machine-local.
- The repo itself is distributed by `git clone`, not Dropbox sync — never
  depend on Dropbox for repo state on a new machine.

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

## adobe-cc

- The cask installs only the Creative Cloud desktop app. Sign in, then
  install individual Adobe apps from inside it. Uninstalling the cask removes
  only the CC app itself.

## hardening

A settings unit, not an app: selecting it applies a security baseline, every
`update.sh` run re-applies it (drift correction), and deselecting with `zap`
restores macOS defaults. Every run asks for your admin password once.
Design and rationale: `docs/superpowers/specs/2026-09-04-macos-hardening-design.md`.

**What it changes:** application firewall on with stealth mode and logging;
guest login and SMB guest access off; automatic login removed; every automatic
software-update option on (including macOS and App Store); all filename
extensions shown in Finder; Touch ID accepted by `sudo`.

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
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --getstealthmode --getloggingmode
defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled          # 0
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates  # 1
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
