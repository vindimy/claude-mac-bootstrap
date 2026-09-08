#!/bin/bash
# shellcheck disable=SC2034
# VLC media player — Homebrew cask (auto-updates itself once installed).
APP_NAME="VLC"
APP_CATEGORY="Media"

vlc_install()   { cask_install vlc; }
vlc_update()    { cask_update vlc; }
vlc_uninstall() { cask_uninstall vlc "$1"; }
vlc_installed() { cask_installed vlc; }
