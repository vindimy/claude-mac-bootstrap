#!/bin/bash
# shellcheck disable=SC2034
# Google Gemini desktop app (gemini.google/mac) — Homebrew cask google-gemini.
APP_NAME="Google Gemini Desktop"
APP_CATEGORY="AI"

gemini_install()   { cask_install google-gemini; }
gemini_update()    { cask_update google-gemini; }
gemini_uninstall() { cask_uninstall google-gemini "$1"; }
gemini_installed() { cask_installed google-gemini; }
