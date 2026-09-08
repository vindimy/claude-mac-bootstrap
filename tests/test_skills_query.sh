#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs

# listing + parser (fake CLI)
out="$(skills_list_upstream acme/tools)"
assert_eq "$(printf 'alpha\tFirst skill, does alpha things\nbeta\tSecond skill, does beta things\ngamma\tThird skill, does gamma things')" "$out" "parses names and first description line"
assert_eq "alpha beta gamma" "$(skills_upstream_names acme/tools)" "names joined by spaces"
assert_eq "1" "$(grep -c 'add acme/tools -l' "$FAKE_NPX_LOG")" "listing hit the CLI once"
skills_upstream_names acme/tools >/dev/null
assert_eq "1" "$(grep -c 'add acme/tools -l' "$FAKE_NPX_LOG")" "second call served from cache"
assert_fail "unknown repo (no skills found) fails" skills_list_upstream acme/nothing
FAKE_NPX_LIST_FAIL=1 assert_fail "CLI failure propagates" skills_list_upstream acme/other

# parser against a real capture (ANSI, box drawing, wrapped description)
real="$(skills_parse_listing <"$TESTS_DIR/fixtures/real-list-gsd-pi.txt")"
assert_eq "gsd-orchestrator" "$(printf '%s\n' "$real" | cut -f1)" "real capture: name"
assert_contains "$(printf '%s\n' "$real" | cut -f2)" "Build software products autonomously" "real capture: description"

# lock file
assert_eq "" "$(skills_lock_names acme/tools)" "no lock file -> empty"
npx -y skills add acme/tools -g -y -s alpha beta >/dev/null
npx -y skills add acme/suite -g -y -s one >/dev/null
assert_eq "$(printf 'alpha\nbeta')" "$(skills_lock_names acme/tools)" "lock names filtered by source"
assert_ok "lock_has known" skills_lock_has one
assert_fail "lock_has unknown" skills_lock_has gamma

# agents
assert_eq "$HOME/.codex/skills" "$(skills_agent_dir codex)" "codex dir"
assert_ok "star agents always ready" skills_agents_ready "*"
assert_eq "$HOME/.codex" "$(skills_agent_home codex)" "codex home"
assert_ok "codex ready when installed" skills_agents_ready codex
rm -rf "$HOME/.codex"
assert_fail "codex not ready when not installed" skills_agents_ready codex

# roster helpers
R="a/one|*|x y
b/two|codex|*"
assert_eq "2" "$(skills_roster_count "$R")" "count"
assert_eq "b/two|codex|*" "$(skills_roster_record "$R" 2)" "record 2"
assert_eq "x y" "$(skills_roster_field "$(skills_roster_record "$R" 1)" 3)" "field 3"
assert_eq "codex" "$(skills_roster_field "b/two|codex|*" 2)" "field 2"
finish
