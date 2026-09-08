#!/bin/bash
# shellcheck disable=SC2034
# HandBrake video transcoder — Homebrew cask (auto-updates itself once installed).
# Cask `handbrake-app`, not `handbrake`: the latter is the formula for the
# HandBrakeCLI command-line tool. This one installs "HandBrake.app".
APP_NAME="HandBrake"
APP_CATEGORY="Media"

handbrake_install()   { cask_install handbrake-app; }
handbrake_update()    { cask_update handbrake-app; }
handbrake_uninstall() { cask_uninstall handbrake-app "$1"; }
handbrake_installed() { cask_installed handbrake-app; }
