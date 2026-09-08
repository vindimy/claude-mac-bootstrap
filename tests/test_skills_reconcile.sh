#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
# shellcheck disable=SC2012
store_ls() { ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//'; }

# explicit list installs exactly those names for all agents
skills_reconcile acme/tools "*" "alpha beta"
assert_eq "alpha beta" "$(store_ls)" "explicit add"
assert_contains "$(npx_log)" "skills add acme/tools -g -y -s alpha beta" "add command shape"
assert_not_contains "$(npx_log)" " -a " "no -a for star agents"

# shrinking the list removes the stale name (lock - selected)
skills_reconcile acme/tools "*" "alpha"
assert_eq "alpha" "$(store_ls)" "stale removed"
assert_contains "$(npx_log)" "skills remove -g -y beta" "remove only the stale name"

# star: installs with -s '*' and removes lock names no longer upstream
mkdir -p "$HOME/.agents/skills/ghost"
python3 - "$HOME/.agents/.skill-lock.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["skills"]["ghost"] = {"source": "acme/tools"}
json.dump(d, open(sys.argv[1], "w"))
PY
skills_reconcile acme/tools "*" "*"
assert_contains "$(npx_log)" "skills add acme/tools -g -y -s *" "star passed literally"
assert_eq "alpha beta gamma" "$(store_ls)" "star installs all, ghost removed"
assert_contains "$(npx_log)" "skills remove -g -y ghost" "ghost removed by name"

# codex-only agents flag, comma-joined
skills_reconcile acme/suite "codex" "one"
assert_contains "$(npx_log)" "skills add acme/suite -g -y -a codex -s one" "agents flag"
assert_ok "linked into codex" test -L "$HOME/.codex/skills/one"
assert_fail "not linked into claude" test -e "$HOME/.claude/skills/one"

# missing agent dir -> skipped, exit 0, nothing run
: >"$FAKE_NPX_LOG"
rm -rf "$HOME/.codex"
assert_ok "skip is not a failure" skills_reconcile acme/suite "codex" "two"
assert_eq "" "$(npx_log)" "nothing invoked when agent dir missing"
mkdir -p "$HOME/.codex/skills"

# empty selection: no add, stale removal still happens
skills_reconcile acme/suite "codex" ""
assert_not_contains "$(npx_log)" "add acme/suite" "no add for empty selection"
assert_contains "$(npx_log)" "skills remove -g -y one" "empty selection removes previous"

# failures propagate
FAKE_NPX_FAIL=1 assert_fail "add failure -> non-zero" skills_reconcile acme/tools "*" "alpha"

# dry run: prints, changes nothing
: >"$FAKE_NPX_LOG"
out="$(DRY_RUN=1 skills_reconcile acme/suite "*" "two")"
assert_contains "$out" "[dry-run] npx -y skills add acme/suite -g -y -s two" "dry-run echoes add"
assert_eq "" "$(npx_log)" "dry-run does not call the CLI"

# purge: untracked copies go, tracked ones stay
mkdir -p "$HOME/.agents/skills/leftover" "$HOME/.claude/skills/leftover-link-target"
ln -s "$HOME/.claude/skills/leftover-link-target" "$HOME/.claude/skills/leftover"
skills_purge_untracked "leftover alpha nonexistent"
assert_fail "untracked store dir removed" test -e "$HOME/.agents/skills/leftover"
assert_fail "untracked agent link removed" test -L "$HOME/.claude/skills/leftover"
assert_ok "tracked skill kept" test -d "$HOME/.agents/skills/alpha"
finish
