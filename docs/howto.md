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
