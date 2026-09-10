#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
mcp_log() { cat "$FAKE_MCP_LOG"; }
state() { grep -v '^#' "$(mcp_state_file)" 2>/dev/null; }
# lib/mcp.sh reaches Claude Code through ~/.local/bin/claude (the native
# installer's path); point the sandbox copy at the fake.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\nexec fake-mcp-cli claude "$@"\n' >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"

# ---- roster parsing ----
MCP_ROSTER_FILE="$SANDBOX/roster.conf"
printf '# comment\n\ncontext7|stdio|npx -y @upstash/context7-mcp\ngithub|stdio|~/.local/bin/github-mcp.sh\nsentry|http|https://mcp.sentry.dev/mcp\n' >"$MCP_ROSTER_FILE"
assert_eq "3" "$(mcp_roster_records | wc -l | tr -d ' ')" "comments and blanks skipped"
rec="$(mcp_roster_records | sed -n 2p)"
assert_eq "github" "$(mcp_record_name "$rec")" "name field"
assert_eq "stdio" "$(mcp_record_transport "$rec")" "transport field"
# shellcheck disable=SC2088  # the label text below is a literal string, not an expansion
assert_eq "$HOME/.local/bin/github-mcp.sh" "$(mcp_record_target "$rec")" "~/ expanded to HOME"
assert_eq "npx -y @upstash/context7-mcp" "$(mcp_record_target "$(mcp_roster_records | sed -n 1p)")" "args kept"
assert_ok "valid record" mcp_record_valid "$rec"
assert_fail "bad name" mcp_record_valid "bad name|stdio|x"
assert_fail "bad transport" mcp_record_valid "x|sse|x"
assert_fail "empty target" mcp_record_valid "x|stdio|"
MCP_ROSTER_FILE="$SANDBOX/missing.conf"
assert_fail "missing roster -> rc 1" mcp_roster_records
MCP_ROSTER_FILE="$SANDBOX/roster.conf"

# ---- agents ----
assert_eq "claude codex gemini" "$(mcp_ready_agents)" "all three fakes ready"
assert_eq "$HOME/.local/bin/claude" "$(mcp_agent_cli claude)" "claude via ~/.local/bin"
assert_eq "codex" "$(mcp_agent_cli codex)" "codex via PATH"

# ---- per-agent add shapes ----
: >"$FAKE_MCP_LOG"
mcp_agent_add claude "context7|stdio|npx -y @upstash/context7-mcp"
mcp_agent_add codex  "context7|stdio|npx -y @upstash/context7-mcp"
mcp_agent_add gemini "context7|stdio|npx -y @upstash/context7-mcp"
assert_contains "$(mcp_log)" "claude mcp add -s user context7 -- npx -y @upstash/context7-mcp" "claude stdio shape"
assert_contains "$(mcp_log)" "codex mcp add context7 -- npx -y @upstash/context7-mcp" "codex stdio shape"
assert_contains "$(mcp_log)" "gemini mcp add -s user context7 -- npx -y @upstash/context7-mcp" "gemini stdio shape"
mcp_agent_add claude "sentry|http|https://mcp.sentry.dev/mcp"
mcp_agent_add codex  "sentry|http|https://mcp.sentry.dev/mcp"
mcp_agent_add gemini "sentry|http|https://mcp.sentry.dev/mcp"
assert_contains "$(mcp_log)" "claude mcp add -s user --transport http sentry https://mcp.sentry.dev/mcp" "claude http shape"
assert_contains "$(mcp_log)" "codex mcp add sentry --url https://mcp.sentry.dev/mcp" "codex http shape"
assert_contains "$(mcp_log)" "gemini mcp add -s user -t http sentry https://mcp.sentry.dev/mcp" "gemini http shape"
mcp_agent_add gemini "gh|stdio|~/.local/bin/github-mcp.sh"
assert_contains "$(mcp_log)" "gemini mcp add -s user gh -- $HOME/.local/bin/github-mcp.sh" "target expanded when adding"
assert_fail "unknown transport rejected" mcp_agent_add claude "x|sse|y"

# ---- detection ----
assert_ok "claude has (mcp get)" mcp_agent_has claude context7
assert_ok "codex has (mcp get)" mcp_agent_has codex sentry
assert_ok "gemini has (settings.json)" mcp_agent_has gemini sentry
assert_fail "absent" mcp_agent_has codex nosuch
rm -f "$HOME/.gemini/settings.json"
assert_fail "gemini without settings.json -> absent" mcp_agent_has gemini sentry
printf 'not json' >"$HOME/.gemini/settings.json"
assert_fail "gemini unparsable settings.json -> absent" mcp_agent_has gemini sentry

# ---- remove shapes ----
: >"$FAKE_MCP_LOG"
mcp_agent_remove claude context7
mcp_agent_remove codex context7
mcp_agent_remove gemini context7
assert_contains "$(mcp_log)" "claude mcp remove -s user context7" "claude remove shape"
assert_contains "$(mcp_log)" "codex mcp remove context7" "codex remove shape"
assert_contains "$(mcp_log)" "gemini mcp remove -s user context7" "gemini remove shape"
assert_fail "removed" mcp_agent_has claude context7
for a in claude codex gemini; do mcp_agent_remove "$a" sentry; done
mcp_agent_remove gemini gh
out="$(DRY_RUN=1 mcp_agent_add codex "dry|stdio|echo hi")"
assert_contains "$out" "[dry-run] codex mcp add dry -- echo hi" "dry-run add prints"
assert_fail "dry-run add does not add" mcp_agent_has codex dry

finish
