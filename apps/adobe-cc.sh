#!/bin/bash
# shellcheck disable=SC2034
# Adobe Creative Cloud — Homebrew cask installs the CC desktop app (auto-updates
# itself); individual Adobe apps are installed from inside it after sign-in.
# Uninstalling the cask removes only the CC desktop app, not Adobe apps
# installed through it — remove those from the CC app first.
APP_NAME="Adobe Creative Cloud"
APP_NOTE="Sign in to the Creative Cloud app after install, then install individual Adobe apps from it."

adobe_cc_install()   { cask_install adobe-creative-cloud; }
adobe_cc_update()    { cask_update adobe-creative-cloud; }
adobe_cc_uninstall() { cask_uninstall adobe-creative-cloud "$1"; }
adobe_cc_installed() { cask_installed adobe-creative-cloud; }
