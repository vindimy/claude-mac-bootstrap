#!/bin/bash
# Persistent "auto memory" is pinned off for every managed agent CLI:
# Claude Code via the managed settings.json, Codex via ~/.codex/config.toml,
# Gemini CLI via ~/.gemini/settings.json. Covers the TOML/JSON config drivers
# the codex and gemini-cli units use, and the units' apply steps.
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
discover_apps

# ---- toml driver -------------------------------------------------------------
T="$SANDBOX/config.toml"

assert_fail "missing file -> not set" toml_bool_is "$T" features memories false
assert_ok "set creates the file" toml_set_bool "$T" features memories false
assert_ok "set is readable back" toml_bool_is "$T" features memories false
assert_eq "$(printf '[features]\nmemories = false')" "$(cat "$T")" "fresh file holds just the table"

# an existing table: the key is replaced in place, neighbours and other tables survive
cat >"$T" <<'EOF'
model = "gpt-5"

[features]
memories = true
apps = true

[other]
memories = true

[mcp_servers.x]
command = "npx"
EOF
assert_fail "true is not false" toml_bool_is "$T" features memories false
toml_set_bool "$T" features memories false
assert_ok "replaced in place" toml_bool_is "$T" features memories false
assert_eq "1" "$(grep -c '^memories = false' "$T")" "exactly one memories line under features"
assert_ok "neighbour key kept" toml_bool_is "$T" features apps true
assert_ok "same key in another table untouched" toml_bool_is "$T" other memories true
assert_contains "$(cat "$T")" 'model = "gpt-5"' "top-level key kept"
assert_contains "$(cat "$T")" '[mcp_servers.x]' "dotted table header kept"
before="$(cat "$T")"
toml_set_bool "$T" features memories false
assert_eq "$before" "$(cat "$T")" "idempotent: second set changes nothing"

# table absent: appended, existing content untouched
printf '[other]\nmemories = true\n' >"$T"
toml_set_bool "$T" memories generate_memories false
assert_eq "$(printf '[other]\nmemories = true\n\n[memories]\ngenerate_memories = false')" "$(cat "$T")" "table appended after existing content"

# a second key in the same table goes under the same header
toml_set_bool "$T" memories use_memories false
assert_eq "1" "$(grep -c '^\[memories\]' "$T")" "table header not duplicated"
assert_ok "second key set" toml_bool_is "$T" memories use_memories false
assert_ok "first key still set" toml_bool_is "$T" memories generate_memories false

# top-level dotted form: read, then folded into the table on set
printf 'features.memories = true\n' >"$T"
assert_ok "dotted form is read" toml_bool_is "$T" features memories true
toml_set_bool "$T" features memories false
assert_ok "dotted form overridden" toml_bool_is "$T" features memories false
assert_not_contains "$(cat "$T")" "features.memories" "dotted line removed so the table is not a duplicate key"

# trailing comment and odd spacing on the value line
printf '[features]\n  memories=true   # tried it\n' >"$T"
assert_ok "comment/spacing tolerated on read" toml_bool_is "$T" features memories true
toml_set_bool "$T" features memories false
assert_ok "comment/spacing tolerated on set" toml_bool_is "$T" features memories false

# dry-run prints and writes nothing
printf '[features]\nmemories = true\n' >"$T"
out="$(DRY_RUN=1 toml_set_bool "$T" features memories false)"
assert_contains "$out" "[dry-run] set memories = false in [features] of $T" "dry-run prints the edit"
assert_ok "dry-run leaves the file alone" toml_bool_is "$T" features memories true
rm -f "$T"
out="$(DRY_RUN=1 toml_set_bool "$T" features memories false)"
assert_fail "dry-run creates nothing" test -e "$T"

# ---- json driver -------------------------------------------------------------
J="$SANDBOX/settings.json"

assert_fail "missing file -> not set" json_bool_is "$J" experimental.autoMemory false
assert_ok "set creates the file" json_set_bool "$J" experimental.autoMemory false
assert_ok "set is readable back" json_bool_is "$J" experimental.autoMemory false
assert_eq '{"experimental": {"autoMemory": false}}' "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$J")" "fresh file holds just the key"

# existing content and sibling keys survive; the value flips
cat >"$J" <<'EOF'
{
  "mcpServers": {"context7": {"command": "npx"}},
  "experimental": {"autoMemory": true, "other": 1}
}
EOF
assert_fail "true is not false" json_bool_is "$J" experimental.autoMemory false
json_set_bool "$J" experimental.autoMemory false
assert_ok "flipped" json_bool_is "$J" experimental.autoMemory false
assert_eq '{"experimental": {"autoMemory": false, "other": 1}, "mcpServers": {"context7": {"command": "npx"}}}' \
  "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$J")" "siblings and other top-level keys kept"

# an unparsable file is refused, never clobbered
printf 'not json' >"$J"
err_out="$(json_set_bool "$J" experimental.autoMemory false 2>&1 >/dev/null)"
rc=$?
assert_eq "1" "$rc" "bad JSON -> rc 1"
assert_contains "$err_out" "not valid JSON" "bad JSON is reported"
assert_eq "not json" "$(cat "$J")" "bad JSON left untouched"
assert_fail "bad JSON reads as not set" json_bool_is "$J" experimental.autoMemory false

# dry-run prints and writes nothing
printf '{"experimental": {"autoMemory": true}}\n' >"$J"
out="$(DRY_RUN=1 json_set_bool "$J" experimental.autoMemory false)"
assert_contains "$out" "[dry-run] set experimental.autoMemory = false in $J" "dry-run prints the edit"
assert_ok "dry-run leaves the file alone" json_bool_is "$J" experimental.autoMemory true

# ---- codex unit --------------------------------------------------------------
brew_log() { cat "$FAKE_BREW_LOG"; }
C="$HOME/.codex/config.toml"
rm -rf "$HOME/.codex"

: >"$FAKE_BREW_LOG"
assert_ok "codex install" codex_install
assert_contains "$(brew_log)" "install --cask --adopt codex" "cask still installed"
assert_ok "features.memories off" toml_bool_is "$C" features memories false
assert_ok "generate_memories off" toml_bool_is "$C" memories generate_memories false
assert_ok "use_memories off" toml_bool_is "$C" memories use_memories false

# an existing config with memories turned on is corrected, the rest kept
cat >"$C" <<'EOF'
notify = ["something", "turn-ended"]

[features]
memories = true

[mcp_servers.context7]
command = "npx"
EOF
out="$(codex_update)"
assert_contains "$out" "codex: turning memories off in ~/.codex/config.toml" "update reports the fix"
assert_ok "re-pinned on update" toml_bool_is "$C" features memories false
assert_ok "generate_memories added" toml_bool_is "$C" memories generate_memories false
assert_contains "$(cat "$C")" 'notify = ["something", "turn-ended"]' "unrelated top-level key kept"
assert_contains "$(cat "$C")" '[mcp_servers.context7]' "MCP table kept"
before="$(cat "$C")"
out="$(codex_update)"
assert_eq "" "$out" "already off -> silent"
assert_eq "$before" "$(cat "$C")" "already off -> unchanged"

# dry-run against a config that needs fixing: prints, writes nothing
printf '[features]\nmemories = true\n' >"$C"
out="$(DRY_RUN=1 codex_update)"
assert_contains "$out" "[dry-run] set memories = false in [features] of $C" "dry-run shows the edit"
assert_ok "dry-run changed nothing" toml_bool_is "$C" features memories true

# ---- gemini-cli unit ---------------------------------------------------------
G="$HOME/.gemini/settings.json"
rm -f "$G"

assert_ok "gemini-cli install" gemini_cli_install
assert_ok "autoMemory off after install" json_bool_is "$G" experimental.autoMemory false
assert_ok "skills dir still created" test -d "$HOME/.gemini/skills"

# the mcp-servers unit's entries survive, an enabled flag is corrected
printf '{"mcpServers": {"github": {"command": "gh-mcp"}}, "experimental": {"autoMemory": true}}\n' >"$G"
out="$(gemini_cli_update)"
assert_contains "$out" "gemini-cli: turning Auto Memory off in ~/.gemini/settings.json" "update reports the fix"
assert_ok "re-pinned on update" json_bool_is "$G" experimental.autoMemory false
assert_ok "MCP servers kept" mcp_agent_has gemini github
before="$(cat "$G")"
out="$(gemini_cli_update)"
assert_eq "" "$out" "already off -> silent"
assert_eq "$before" "$(cat "$G")" "already off -> unchanged"

# a broken settings.json fails the unit loudly instead of being overwritten
printf 'not json' >"$G"
assert_fail "broken settings.json -> unit fails" gemini_cli_update
assert_eq "not json" "$(cat "$G")" "broken settings.json untouched"

# ---- claude-code: the managed settings file pins it ------------------------
assert_eq "False" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("autoMemoryEnabled"))' "$REPO_ROOT/dotfiles/.claude/settings.json")" "repo settings.json sets autoMemoryEnabled false"

finish
