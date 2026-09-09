#!/bin/bash
# shellcheck disable=SC2034
# GitHub CLI — Homebrew formula. Issues in this repo are tracked through it
# (docs/agents/issue-tracker.md); `gh auth login` is a one-time manual step.
APP_NAME="GitHub CLI"
APP_CATEGORY="Development"
APP_NOTE="Run 'gh auth login' once (browser or token) so issue and PR commands work."

gh_install()   { formula_install gh; }
gh_update()    { formula_update gh; }
gh_uninstall() { formula_uninstall gh "$1"; }
gh_installed() { formula_installed gh; }
