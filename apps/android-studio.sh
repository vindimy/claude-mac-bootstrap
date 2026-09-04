#!/bin/bash
# shellcheck disable=SC2034
# Android Studio — Homebrew cask (auto-updates itself once installed).
# The IDE manages the Android SDK/emulators itself; the managed .zprofile
# exports ANDROID_HOME and puts platform-tools on PATH when the SDK exists.
APP_NAME="Android Studio"
APP_NOTE="Run the first-launch setup wizard once to download the Android SDK and emulator."

android_studio_install()   { cask_install android-studio; }
android_studio_update()    { cask_update android-studio; }
android_studio_uninstall() { cask_uninstall android-studio "$1"; }
android_studio_installed() { cask_installed android-studio; }
