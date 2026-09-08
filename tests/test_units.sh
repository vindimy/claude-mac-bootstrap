#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
discover_apps

has() { in_list "$1" "${APP_IDS[*]}"; }
assert_ok "agent-skills discovered" has agent-skills
assert_ok "agent-skill-suites discovered" has agent-skill-suites
assert_eq "Agent skills (curated task packs)" "$(app_name_for agent-skills)" "renamed"
assert_eq "Agent skill suites" "$(app_name_for agent-skill-suites)" "suites name"
assert_eq "" "$(app_note_for agent-skills)" "local-only note gone"

# rosters: shape and key facts from the spec
assert_eq "6" "$(skills_roster_count "$AGENT_SKILLS_ROSTER")" "task packs: 6 repos"
assert_eq "4" "$(skills_roster_count "$AGENT_SKILL_SUITES_ROSTER")" "suites: 4 repos"
assert_eq "obra/superpowers|codex|*" "$(skills_roster_record "$AGENT_SKILL_SUITES_ROSTER" 1)" "superpowers codex-only, track all"
assert_eq "mattpocock/skills|*|*" "$(skills_roster_record "$AGENT_SKILL_SUITES_ROSTER" 2)" "mattpocock track all"
assert_eq "open-gsd/gsd-pi|*|*" "$(skills_roster_record "$AGENT_SKILL_SUITES_ROSTER" 3)" "gsd-pi track all"
cek="$(skills_roster_record "$AGENT_SKILL_SUITES_ROSTER" 4)"
assert_eq "NeoLabHQ/context-engineering-kit" "$(skills_roster_field "$cek" 1)" "cek repo"
assert_eq "22" "$(skills_roster_field "$cek" 3 | wc -w | tr -d ' ')" "cek default subset size"
assert_not_contains " $(skills_roster_field "$cek" 3) " " test-driven-development " "cek excludes colliding name"
acs="$(skills_roster_record "$AGENT_SKILLS_ROSTER" 6)"
assert_eq "ComposioHQ/awesome-claude-skills" "$(skills_roster_field "$acs" 1)" "awesome-claude-skills added"
assert_eq "19" "$(skills_roster_field "$acs" 3 | wc -w | tr -d ' ')" "acs default 19"
assert_contains " $(skills_roster_field "$acs" 3) " " youtube-downloader " "renamed skill uses new name"
assert_eq "30" "$(skills_roster_field "$(skills_roster_record "$AGENT_SKILLS_ROSTER" 1)" 3 | wc -w | tr -d ' ')" "softaworks 30 kept"
assert_eq "video-downloader" "$AGENT_SKILLS_PURGE" "task packs purge"
assert_eq "12" "$(printf '%s\n' "$AGENT_SKILL_SUITES_PURGE" | wc -w | tr -d ' ')" "suites purge: graphify + 11"
assert_contains " $AGENT_SKILL_SUITES_PURGE " " graphify " "purge has graphify"
assert_contains " $AGENT_SKILL_SUITES_PURGE " " caveman " "purge has a culled name"

# unit names are baked in, not read from $APP_NAME at call time
# shellcheck disable=SC2034  # deliberately clobbered to prove units do not read it
APP_NAME="something else"
skills_conf_put obra/superpowers "*"   # gives the unit a saved line so the reselect prompt (which names the unit) appears
screen="$(printf '\n' | NON_INTERACTIVE=0 DRY_RUN=1 agent_skill_suites_update 2>&1 >/dev/null)"
assert_contains "$screen" "Reselect skills for Agent skill suites?" "unit name baked in"
assert_not_contains "$screen" "something else" "unit does not use APP_NAME at call time"

# dry-run of the real rosters against the fake CLI: star repos still emit add;
# explicit repos emit add with their default names
unset SKILLS_SYNCED_UNITS
rm -f "$(skills_conf_file)"
out="$(DRY_RUN=1 agent_skill_suites_install 2>/dev/null)"
assert_contains "$out" "[dry-run] npx -y skills add obra/superpowers -g -y -a codex -s *" "superpowers dry-run add"
assert_contains "$out" "[dry-run] npx -y skills add NeoLabHQ/context-engineering-kit -g -y -s context-engineering" "cek dry-run add"
finish
