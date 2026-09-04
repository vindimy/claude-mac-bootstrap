#!/bin/bash
# shellcheck disable=SC2034
# OpenAI ChatGPT desktop — Homebrew cask (auto-updates itself once installed).
APP_NAME="ChatGPT"
APP_CATEGORY="AI"

chatgpt_install()   { cask_install chatgpt; }
chatgpt_update()    { cask_update chatgpt; }
chatgpt_uninstall() { cask_uninstall chatgpt "$1"; }
chatgpt_installed() { cask_installed chatgpt; }
