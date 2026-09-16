#!/bin/bash
# shellcheck disable=SC2034
# GitLab CLI — Homebrew formula. The GitLab counterpart of `gh`; `glab auth
# login` is a one-time manual step (self-hosted instances take --hostname).
APP_NAME="GitLab CLI"
APP_CATEGORY="Development"
APP_NOTE="Run 'glab auth login' once (add --hostname for a self-hosted GitLab) so issue and MR commands work."

glab_install()   { formula_install glab; }
glab_update()    { formula_update glab; }
glab_uninstall() { formula_uninstall glab "$1"; }
glab_installed() { formula_installed glab; }
