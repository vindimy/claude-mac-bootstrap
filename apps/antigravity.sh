#!/bin/bash
# shellcheck disable=SC2034
# Google Antigravity — agentic IDE, Homebrew cask (auto-updates itself once
# installed).
APP_NAME="Google Antigravity"
APP_CATEGORY="AI"

antigravity_install()   { cask_install antigravity; }
antigravity_update()    { cask_update antigravity; }
antigravity_uninstall() { cask_uninstall antigravity "$1"; }
antigravity_installed() { cask_installed antigravity; }
