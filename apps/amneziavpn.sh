#!/bin/bash
# shellcheck disable=SC2034
# Amnezia VPN client — Homebrew cask (pkg installer; prompts for admin password).
APP_NAME="Amnezia VPN"
APP_CATEGORY="VPN"

amneziavpn_install()   { cask_install amneziavpn; }
amneziavpn_update()    { cask_update amneziavpn; }
amneziavpn_uninstall() { cask_uninstall amneziavpn "$1"; }
amneziavpn_installed() { cask_installed amneziavpn; }
