#!/bin/bash
# shellcheck disable=SC2034
# Colima — headless Docker engine that survives reboot. A LaunchDaemon
# (system domain, runs at boot before anyone logs in) starts the VM as
# $USER; containers with a --restart policy come back once dockerd is up.
# Docker Desktop can't do this: it is a per-user GUI app, so its engine —
# a separate container store — only exists while someone is logged in.
# If the VM won't start pre-login with the default vz driver, fall back to
# `colima start --vm-type qemu` (see APP_NOTE validation step).
APP_NAME="Colima (headless Docker engine)"
APP_CATEGORY="Development"
APP_NOTE="Reboot-surviving containers belong in the colima context (docker context use colima) and need --restart unless-stopped. Boot-time start requires FileVault to stay OFF on this machine. Validate once: reboot without logging in and check the containers from another machine."

COLIMA_FORMULAS="colima docker docker-compose"
COLIMA_DAEMON_LABEL="dev.colima"
COLIMA_DAEMON_PLIST="/Library/LaunchDaemons/$COLIMA_DAEMON_LABEL.plist"

colima_write_daemon_plist() {
  local brew_bin
  brew_bin="$(dirname "$(command -v brew)")"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] write $COLIMA_DAEMON_PLIST (colima start --foreground as $USER)"
    return 0
  fi
  sudo tee "$COLIMA_DAEMON_PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$COLIMA_DAEMON_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$brew_bin/colima</string>
    <string>start</string>
    <string>--foreground</string>
  </array>
  <key>UserName</key><string>$USER</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$HOME</string>
    <key>PATH</key><string>$brew_bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/colima.launchd.log</string>
  <key>StandardErrorPath</key><string>/tmp/colima.launchd.log</string>
</dict>
</plist>
EOF
  run_cmd sudo chown root:wheel "$COLIMA_DAEMON_PLIST"
  run_cmd sudo chmod 644 "$COLIMA_DAEMON_PLIST"
}

colima_install() {
  local f
  for f in $COLIMA_FORMULAS; do
    formula_update "$f" || return 1
  done
  # First start runs interactively so VM creation (image download, vz setup)
  # and the docker context land while errors are visible; the daemon then
  # owns the VM from its next start.
  run_cmd colima start || return 1
  run_cmd docker context use colima
  run_cmd colima stop
  colima_write_daemon_plist || return 1
  # Idempotent reload: bootout is a no-op error when not loaded — tolerate.
  run_cmd sudo launchctl bootout "system/$COLIMA_DAEMON_LABEL" 2>/dev/null
  run_cmd sudo launchctl bootstrap system "$COLIMA_DAEMON_PLIST"
}

colima_update() {
  local f
  if ! colima_installed && [ "$DRY_RUN" != 1 ]; then
    colima_install
    return
  fi
  # Formula upgrades only; the running VM and daemon are left alone.
  for f in $COLIMA_FORMULAS; do
    formula_update "$f" || return 1
  done
}

colima_uninstall() {
  local f
  run_cmd sudo launchctl bootout "system/$COLIMA_DAEMON_LABEL" 2>/dev/null
  run_cmd sudo rm -f "$COLIMA_DAEMON_PLIST"
  if command -v colima >/dev/null 2>&1; then
    run_cmd colima stop
    if [ "${1:-keep}" = zap ]; then
      # Deletes the VM and every container/volume in it.
      run_cmd colima delete --force
    fi
  fi
  for f in $COLIMA_FORMULAS; do
    formula_uninstall "$f"
  done
}

colima_installed() {
  formula_installed colima && [ -f "$COLIMA_DAEMON_PLIST" ]
}
