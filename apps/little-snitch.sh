#!/bin/bash
# shellcheck disable=SC2034
# Little Snitch — Homebrew cask. Needs a manual one-time system-extension
# approval after install; license/rules are never touched by this repo.
APP_NAME="Little Snitch"
APP_CATEGORY="System Tools"
APP_NOTE="Approve the Little Snitch system extension in System Settings > General > Login Items & Extensions, then enter your license."

little_snitch_install()   { cask_install little-snitch; }
little_snitch_update()    { cask_update little-snitch; }
little_snitch_uninstall() { cask_uninstall little-snitch "$1"; }
little_snitch_installed() { cask_installed little-snitch; }
