#!/bin/bash
# bin/claude-context-audit.sh: the pure pieces (summary parsing, history,
# growth, staleness) plus --due / --dry-run, without Node or network.
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs

AUDIT="$REPO_ROOT/bin/claude-context-audit.sh"
export CLAUDE_CONTEXT_AUDIT_STATE="$SANDBOX/audit-state"
# "claude installed" is keyed on the native install path, like the unit.
mkdir -p "$HOME/.local/bin" && : >"$HOME/.local/bin/claude" && chmod +x "$HOME/.local/bin/claude"

# shellcheck source=/dev/null
CLAUDE_CONTEXT_AUDIT_LIB=1 . "$AUDIT"
due_quiet() { "$AUDIT" --due >/dev/null; }
bogus_quiet() { "$AUDIT" --bogus >/dev/null 2>&1; }

# --- summary line parsing ---------------------------------------------------
line='[agent-proxy] 69 tools · 154,946 tool bytes · 65,538 real input tokens'
assert_eq "$(printf '69\t154946\t65538')" "$(cca_parse_summary "$line")" "parse summary with tokens"
line_no_tok='[agent-proxy] 12 tools · 20,001 tool bytes'
assert_eq "$(printf '12\t20001\t')" "$(cca_parse_summary "$line_no_tok")" "parse summary without tokens"
assert_fail "parse rejects non-summary" cca_parse_summary "  Workflow  21229 B  ~5307 tok"

# --- picking the main request out of a proxy log ----------------------------
proxy_out="$SANDBOX/proxy.out"
cat >"$proxy_out" <<'LOG'
[agent-proxy] listening on http://localhost:8787

[agent-proxy] 3 tools · 1,200 tool bytes · 900 real input tokens
  Read    600 B  ~150 tok
  logs/a.md

[agent-proxy] 69 tools · 154,946 tool bytes · 65,538 real input tokens
  Workflow      21229 B  ~5307 tok
  DesignSync     8978 B  ~2245 tok
  … 57 more
  logs/b.md

LOG
assert_eq "[agent-proxy] 69 tools · 154,946 tool bytes · 65,538 real input tokens" "$(cca_pick_summary "$proxy_out")" "pick the largest request"
block="$(cca_report_block "$proxy_out")"
assert_contains "$block" "Workflow      21229 B" "report block has the ranked table"
assert_contains "$block" "logs/b.md" "report block ends with the log path"
assert_not_contains "$block" "logs/a.md" "report block skips the small side request"
: >"$SANDBOX/empty.out"
assert_fail "pick fails on a log with no summary" cca_pick_summary "$SANDBOX/empty.out"

# --- top-N trimming keeps the summary, the "more" line and the log path -----
top="$(cca_report_top "$proxy_out" 1)"
assert_contains "$top" "69 tools" "top-1 keeps the summary"
assert_contains "$top" "Workflow      21229 B" "top-1 keeps the first row"
assert_not_contains "$top" "DesignSync" "top-1 drops the second row"
assert_contains "$top" "… 57 more" "top-1 keeps the overflow line"
assert_contains "$top" "logs/b.md" "top-1 keeps the log path"

# --- growth ------------------------------------------------------------------
assert_eq "10" "$(cca_growth_pct 60000 66000)" "growth +10%"
assert_eq "-10" "$(cca_growth_pct 60000 54000)" "growth -10%"
assert_eq "" "$(cca_growth_pct "" 54000)" "no baseline -> empty"
assert_eq "" "$(cca_growth_pct 0 54000)" "zero baseline -> empty"

# --- history -----------------------------------------------------------------
hist="$SANDBOX/history.tsv"
assert_eq "" "$(cca_history_last "$hist")" "no history -> empty"
cca_history_append "$hist" 2026-09-08 69 154946 65538 "headless global"
assert_eq "$(printf 'date\ttools\ttool_bytes\tinput_tokens\tmode')" "$(head -1 "$hist")" "history header written once"
cca_history_append "$hist" 2026-10-08 70 160000 70000 "headless global"
assert_eq "3" "$(wc -l <"$hist" | tr -d ' ')" "header + 2 rows"
assert_eq "$(printf '2026-10-08\t70\t160000\t70000\theadless global')" "$(cca_history_last "$hist")" "last row"
assert_eq "70000" "$(cca_history_last_tokens "$hist")" "last tokens"

# --- --due: stamp staleness, keyed on claude being installed -----------------
stamp="$CLAUDE_CONTEXT_AUDIT_STATE/last-run.stamp"
assert_ok "due when never run" due_quiet
mkdir -p "$CLAUDE_CONTEXT_AUDIT_STATE" && touch "$stamp"
assert_fail "not due right after a run" due_quiet
touch -t "$(date -v-31d +%Y%m%d%H%M)" "$stamp"
assert_ok "due after 31 days" due_quiet
assert_contains "$("$AUDIT" --due)" "31 days" "due message says how old"
rm "$HOME/.local/bin/claude"
assert_fail "not due without claude installed" due_quiet
: >"$HOME/.local/bin/claude" && chmod +x "$HOME/.local/bin/claude"

# --- lib/common.sh nag used by run.sh / update.sh ----------------------------
out="$(context_audit_nag 2>&1)"
assert_contains "$out" "claude-context-audit" "nag names the script when due"
touch "$stamp"
assert_eq "" "$(context_audit_nag 2>&1)" "nag silent when fresh"

# --- --dry-run: shows the plan, touches nothing ------------------------------
touch -t "$(date -v-31d +%Y%m%d%H%M)" "$stamp"
before="$(stat -f %m "$stamp")"
out="$("$AUDIT" --dry-run 2>&1)"
assert_contains "$out" "ANTHROPIC_BASE_URL=http://localhost:" "dry-run shows the probe env"
assert_contains "$out" "claude -p" "dry-run shows the headless probe"
assert_contains "$out" "proxy.mjs" "dry-run mentions the proxy"
assert_eq "$before" "$(stat -f %m "$stamp")" "dry-run leaves the stamp alone"
assert_contains "$("$AUDIT" --dry-run --interactive 2>&1)" "claude)" "dry-run interactive shows a plain claude launch"
assert_contains "$("$AUDIT" --dry-run --here 2>&1)" "$PWD" "dry-run --here probes the current dir"
assert_not_contains "$("$AUDIT" --dry-run 2>&1)" "$PWD" "dry-run default probes the neutral dir"

# --- usage -------------------------------------------------------------------
assert_fail "unknown flag rejected" bogus_quiet
assert_contains "$("$AUDIT" --help)" "Usage:" "help prints usage"
finish
