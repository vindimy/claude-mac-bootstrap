#!/bin/bash
# shellcheck disable=SC2034
# Amnezia VPN client — Homebrew cask (pkg installer; prompts for admin password).
# The cask is an Intel-only pkg, so Apple silicon needs Rosetta 2 before the
# installer will run (ensure_rosetta handles that, one more sudo prompt).
APP_NAME="Amnezia VPN"
APP_CATEGORY="VPN"

amneziavpn_install()   { ensure_rosetta "$APP_NAME" && cask_install amneziavpn; }
amneziavpn_update()    { ensure_rosetta "$APP_NAME" && cask_update amneziavpn; }
amneziavpn_uninstall() { cask_uninstall amneziavpn "$1"; }
amneziavpn_installed() { cask_installed amneziavpn; }
