#!/bin/bash
# shellcheck disable=SC2034
# Docker Desktop — Homebrew cask docker-desktop (auto-updates itself once
# installed). The old `docker` cask name is deprecated in favor of this one.
APP_NAME="Docker Desktop"
APP_NOTE="First launch asks to approve a privileged helper and finish setup — open Docker.app once after install."

docker_install()   { cask_install docker-desktop; }
docker_update()    { cask_update docker-desktop; }
docker_uninstall() { cask_uninstall docker-desktop "$1"; }
docker_installed() { cask_installed docker-desktop; }
