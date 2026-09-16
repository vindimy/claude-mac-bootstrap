#!/bin/bash
# shellcheck disable=SC2034
# OpenAI Codex CLI — Homebrew cask (binary release from github.com/openai/codex;
# does not self-update, so update.sh upgrades it via brew). Also pins Codex's
# persistent memories off in ~/.codex/config.toml on every install/update:
# `features.memories` (the master switch) plus `memories.generate_memories`
# and `memories.use_memories`, so nothing is recorded or injected even if a
# later release flips the default. The Codex VS Code extension and the
# ChatGPT desktop app read the same config.toml, so the setting holds there
# too.
APP_NAME="Codex CLI"
APP_CATEGORY="AI"
APP_NOTE="Memories are pinned off in ~/.codex/config.toml ([features] memories plus [memories] generate_memories/use_memories) on every install/update; the VS Code extension and the ChatGPT app share that file, so turning them on by hand is undone on the next run."

CODEX_CONFIG="$HOME/.codex/config.toml"

codex_memories_off() {
  toml_bool_is "$CODEX_CONFIG" features memories false &&
    toml_bool_is "$CODEX_CONFIG" memories generate_memories false &&
    toml_bool_is "$CODEX_CONFIG" memories use_memories false
}

# Edits only the three keys; everything else in config.toml (MCP servers,
# plugins, the ChatGPT app's own sections) is left as written.
codex_settings_apply() {
  if codex_memories_off; then return 0; fi
  log "codex: turning memories off in ~/.codex/config.toml"
  toml_set_bool "$CODEX_CONFIG" features memories false || return 1
  toml_set_bool "$CODEX_CONFIG" memories generate_memories false || return 1
  toml_set_bool "$CODEX_CONFIG" memories use_memories false
}

codex_install()   { cask_install codex && codex_settings_apply; }
codex_update()    { cask_update codex && codex_settings_apply; }
codex_uninstall() { cask_uninstall codex "$1"; }
codex_installed() { cask_installed codex; }
