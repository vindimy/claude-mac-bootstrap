#!/bin/bash
# shellcheck disable=SC2034
# Cloud CLIs — Azure CLI (az), AWS CLI (aws) and Google Cloud CLI (gcloud)
# under one checklist entry. Azure and AWS are Homebrew formulas; Google
# Cloud only ships as the `gcloud-cli` cask (auto_updates: `gcloud components
# update` keeps it current, brew only reinstalls it when missing). Signing in
# to each cloud is a one-time manual step (see APP_NOTE).
APP_NAME="Cloud CLIs (az, aws, gcloud)"
APP_CATEGORY="Development"
APP_NOTE="Sign in once per cloud: 'az login', 'aws configure' (or 'aws configure sso'), 'gcloud init'. Extra gcloud components land in \$(brew --prefix)/share/google-cloud-sdk/bin — add it to PATH if you install any."

CLOUD_CLIS_FORMULAS="azure-cli awscli"
CLOUD_CLIS_CASK="gcloud-cli"

cloud_clis_install() {
  local f
  for f in $CLOUD_CLIS_FORMULAS; do
    formula_install "$f" || return 1
  done
  cask_install "$CLOUD_CLIS_CASK"
}

# Each driver installs its tool when missing, so a single deleted CLI comes
# back without touching the other two.
cloud_clis_update() {
  local f
  for f in $CLOUD_CLIS_FORMULAS; do
    formula_update "$f" || return 1
  done
  cask_update "$CLOUD_CLIS_CASK"
}

# Formulas have no zap; the mode only reaches the cask.
cloud_clis_uninstall() {
  local f rc=0
  for f in $CLOUD_CLIS_FORMULAS; do
    formula_uninstall "$f" || rc=1
  done
  cask_uninstall "$CLOUD_CLIS_CASK" "${1:-keep}" || rc=1
  return "$rc"
}

cloud_clis_installed() {
  local f
  for f in $CLOUD_CLIS_FORMULAS; do
    formula_installed "$f" || return 1
  done
  cask_installed "$CLOUD_CLIS_CASK"
}
