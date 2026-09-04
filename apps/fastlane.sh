#!/bin/bash
# shellcheck disable=SC2034
# fastlane — Homebrew formula. iOS/Android build, signing, and release
# automation; pairs with the xcode unit for iOS work.
APP_NAME="fastlane"

fastlane_install()   { formula_install fastlane; }
fastlane_update()    { formula_update fastlane; }
fastlane_uninstall() { formula_uninstall fastlane "$1"; }
fastlane_installed() { formula_installed fastlane; }
