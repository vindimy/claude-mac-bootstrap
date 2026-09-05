#!/bin/bash
# shellcheck disable=SC2034
# WhatsApp desktop — Homebrew cask (auto-updates itself once installed).
APP_NAME="WhatsApp"
APP_CATEGORY="Messaging"
APP_NOTE="Open WhatsApp and link the device by scanning the QR code from your phone."

whatsapp_install()   { cask_install whatsapp; }
whatsapp_update()    { cask_update whatsapp; }
whatsapp_uninstall() { cask_uninstall whatsapp "$1"; }
whatsapp_installed() { cask_installed whatsapp; }
