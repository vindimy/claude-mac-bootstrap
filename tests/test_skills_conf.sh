#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs

assert_eq "SKILLS_ComposioHQ__awesome_claude_skills" "$(skills_var_name ComposioHQ/awesome-claude-skills)" "var name sanitises / and -"
assert_fail "get before any save returns 1" skills_conf_get acme/tools

skills_conf_put acme/tools "alpha beta"
assert_eq "alpha beta" "$(skills_conf_get acme/tools)" "get returns saved list"
skills_conf_put acme/suite "*"
assert_eq "*" "$(skills_conf_get acme/suite)" "star round-trips"
skills_conf_put acme/tools ""
assert_ok "empty selection still counts as saved" skills_conf_get acme/tools
assert_eq "" "$(skills_conf_get acme/tools)" "empty value"
assert_eq "*" "$(skills_conf_get acme/suite)" "other repo untouched by rewrite"
assert_eq "1" "$(grep -c '^SKILLS_acme__tools=' "$(skills_conf_file)")" "one line per repo after re-put"

skills_conf_delete acme/tools
assert_fail "deleted repo has no line" skills_conf_get acme/tools
assert_eq "*" "$(skills_conf_get acme/suite)" "delete leaves other repos"

assert_contains "$(head -1 "$(skills_conf_file)")" "Managed by run.sh" "header comment present"
assert_ok "file is valid shell" /bin/bash -n "$(skills_conf_file)"

DRY_RUN=1 skills_conf_put acme/dry "x" >/dev/null
assert_fail "dry-run put writes nothing" skills_conf_get acme/dry
finish
