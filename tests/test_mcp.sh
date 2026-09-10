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

# ---- state ----
mcp_state_put codex context7 "context7|stdio|x"
assert_eq "context7|stdio|x" "$(mcp_state_get codex context7)" "state put/get"
assert_fail "state absent" mcp_state_get claude context7
mcp_state_put codex github "github|stdio|y"
assert_eq "context7 github" "$(mcp_state_names codex | tr '\n' ' ' | sed 's/ $//')" "state names per agent"
mcp_state_delete codex context7
assert_fail "state deleted" mcp_state_get codex context7
assert_eq "1" "$(state | wc -l | tr -d ' ')" "one line left"
mcp_state_delete codex github
assert_eq "0" "$(state | wc -l | tr -d ' ')" "state empty"

# ---- apply: first run adds everything and records it ----
printf 'context7|stdio|npx -y @upstash/context7-mcp\ngithub|stdio|~/.local/bin/github-mcp.sh\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
assert_ok "first apply" mcp_apply
assert_eq "6" "$(grep -c ' mcp add ' "$FAKE_MCP_LOG")" "2 servers x 3 agents added"
assert_eq "6" "$(state | wc -l | tr -d ' ')" "6 state lines"
assert_eq "github|stdio|~/.local/bin/github-mcp.sh" "$(mcp_state_get codex github)" "state stores the raw record"
assert_ok "gemini really has it" mcp_agent_has gemini github

# second run: nothing to do
: >"$FAKE_MCP_LOG"
assert_ok "second apply" mcp_apply
assert_not_contains "$(mcp_log)" " mcp add " "second apply adds nothing"
assert_not_contains "$(mcp_log)" " mcp remove " "second apply removes nothing"

# changed record -> remove then add, on every agent
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\ngithub|stdio|~/.local/bin/github-mcp.sh\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_contains "$(mcp_log)" "claude mcp remove -s user context7" "changed: removed"
assert_contains "$(mcp_log)" "claude mcp add -s user context7 -- npx -y @upstash/context7-mcp@latest" "changed: re-added"
assert_eq "3" "$(grep -c ' mcp remove ' "$FAKE_MCP_LOG")" "changed: one remove per agent"
assert_not_contains "$(mcp_log)" "github-mcp.sh" "unchanged record untouched"
assert_eq "context7|stdio|npx -y @upstash/context7-mcp@latest" "$(mcp_state_get gemini context7)" "state updated"

# dropped from the roster -> removed everywhere, state cleared
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_eq "3" "$(grep -c ' mcp remove .*github' "$FAKE_MCP_LOG")" "dropped: removed from 3 agents"
assert_fail "dropped: state gone" mcp_state_get codex github
assert_fail "dropped: really gone" mcp_agent_has codex github

# a server the user added with a roster name is left alone and never recorded
printf 'mine\n' >>"$FAKE_MCP_DIR/codex"
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nmine|stdio|echo hi\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_not_contains "$(mcp_log)" "codex mcp add mine" "pre-existing user server not re-added"
assert_fail "user server not recorded" mcp_state_get codex mine
assert_contains "$(mcp_log)" "claude mcp add -s user mine -- echo hi" "other agents still get it"
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_contains "$(mcp_log)" "claude mcp remove -s user mine" "managed copy removed"
assert_not_contains "$(mcp_log)" "codex mcp remove mine" "user server not removed"
assert_ok "user server survives" grep -qx mine "$FAKE_MCP_DIR/codex"

# a server the user removed by hand is simply re-added
grep -vx context7 "$FAKE_MCP_DIR/codex" >"$FAKE_MCP_DIR/codex.tmp"; mv "$FAKE_MCP_DIR/codex.tmp" "$FAKE_MCP_DIR/codex"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_contains "$(mcp_log)" "codex mcp add context7 -- npx -y @upstash/context7-mcp@latest" "hand-removed server re-added"

# not-ready agent skipped with a message, no calls
# shellcheck disable=SC2329  # invoked indirectly via mcp_apply -> mcp_ready_agents
mcp_agent_ready() { [ "$1" != gemini ]; }
: >"$FAKE_MCP_LOG"
out="$(mcp_apply 2>&1)"
assert_contains "$out" "mcp: gemini not installed — skipped" "skip message"
assert_not_contains "$(mcp_log)" "gemini " "no gemini calls when not ready"
. "$REPO_ROOT/lib/mcp.sh"

# malformed record: reported, others still applied, rc 1
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nbad name|stdio|x\nok|stdio|echo ok\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
out="$(mcp_apply 2>&1)"; rc=$?
assert_eq "1" "$rc" "malformed record -> rc 1"
assert_contains "$out" "malformed roster record: bad name|stdio|x" "malformed reported"
assert_contains "$(mcp_log)" "codex mcp add ok -- echo ok" "later records still applied"
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\n' >"$MCP_ROSTER_FILE"
mcp_apply

# failed add: reported, pass continues, rc 1, not recorded; retry works
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nnew|stdio|echo new\n' >"$MCP_ROSTER_FILE"
export FAKE_MCP_FAIL=1
assert_fail "failed add returns 1" mcp_apply
assert_fail "failed add not recorded" mcp_state_get claude new
unset FAKE_MCP_FAIL
assert_ok "retry succeeds" mcp_apply
assert_ok "recorded after retry" mcp_state_get claude new

# missing roster: rc 1, nothing touched
MCP_ROSTER_FILE="$SANDBOX/missing.conf"
: >"$FAKE_MCP_LOG"
assert_fail "missing roster -> rc 1" mcp_apply
assert_eq "" "$(mcp_log)" "missing roster -> no calls"
MCP_ROSTER_FILE="$SANDBOX/roster.conf"

# dry-run: prints, mutates nothing
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nnew|stdio|echo new\ndry|stdio|echo dry\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
out="$(DRY_RUN=1 mcp_apply)"
assert_contains "$out" "[dry-run] $HOME/.local/bin/claude mcp add -s user dry -- echo dry" "dry-run echoes add"
assert_not_contains "$(mcp_log)" " mcp add " "dry-run calls no add"
assert_fail "dry-run writes no state" mcp_state_get claude dry

# remove_all: every managed server gone, state file gone, user server kept
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nnew|stdio|echo new\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
assert_ok "remove all" mcp_remove_all
assert_eq "6" "$(grep -c ' mcp remove ' "$FAKE_MCP_LOG")" "every managed server removed"
assert_fail "state file gone" test -f "$(mcp_state_file)"
assert_ok "user server still there" grep -qx mine "$FAKE_MCP_DIR/codex"
assert_fail "managed server really gone" mcp_agent_has gemini context7

finish
