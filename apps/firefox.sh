#!/bin/bash
# shellcheck disable=SC2034
# Mozilla Firefox — Homebrew cask.
APP_NAME="Firefox"

firefox_install()   { cask_install firefox; }
firefox_update()    { cask_update firefox; }
firefox_uninstall() { cask_uninstall firefox "$1"; }
firefox_installed() { cask_installed firefox; }
