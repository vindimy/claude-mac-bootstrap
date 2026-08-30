#!/bin/bash
# shellcheck disable=SC2034
# GSD skill suite (get-shit-done-cc) — 67 gsd-* skills for Claude Code,
# installed as a global npm package. Needs Node.js (brew formula `node`).
APP_NAME="GSD skill suite"
APP_NOTE="For future updates prefer running the gsd-update skill inside Claude Code — it backs up custom files before GSD's clean-install step."

gsd_require_npm() {
  if ! command -v npm >/dev/null 2>&1; then
    log "npm not found — installing Node.js first"
    formula_install node
  fi
  if ! command -v npm >/dev/null 2>&1 && [ "$DRY_RUN" != 1 ]; then
    err "npm still not available — install Node.js and retry"
    return 1
  fi
}

gsd_install() {
  if ! gsd_require_npm; then return 1; fi
  run_cmd npm install -g get-shit-done-cc
}

# npm install -g always moves to latest, so update == install. GSD re-lays
# its managed skill dirs on update; custom skills are preserved, but the
# gsd-update skill's backup-first path is the safer route (see APP_NOTE).
gsd_update() {
  if ! gsd_require_npm; then return 1; fi
  if gsd_installed; then
    log "gsd: updating via npm (safer alternative: the gsd-update skill inside Claude Code)"
  fi
  run_cmd npm install -g get-shit-done-cc
}

# Settings zap does not apply: removal deletes the deployed suite either way.
# GSD lays its files into ~/.claude/skills/gsd-* and ~/.local/bin/gsd-sdk and
# does not necessarily stay resident in the npm global tree, so uninstall
# clears the deployed footprint as well as the package.
gsd_uninstall() {
  local d
  if ! gsd_installed; then
    log "gsd: not installed, nothing to remove"
    return 0
  fi
  if npm ls -g get-shit-done-cc >/dev/null 2>&1; then
    run_cmd npm uninstall -g get-shit-done-cc
  fi
  for d in "$HOME"/.claude/skills/gsd-*; do
    if [ -e "$d" ]; then run_cmd rm -rf "$d"; fi
  done
  if [ -e "$HOME/.local/bin/gsd-sdk" ]; then
    run_cmd rm -f "$HOME/.local/bin/gsd-sdk"
  fi
}

# The deployed footprint, not the npm tree, is the durable evidence: GSD's
# installer lays skills + the gsd-sdk shim and the package may not remain
# listed in `npm ls -g` afterward.
gsd_installed() {
  if [ -x "$HOME/.local/bin/gsd-sdk" ]; then return 0; fi
  ls "$HOME"/.claude/skills/gsd-* >/dev/null 2>&1
}
