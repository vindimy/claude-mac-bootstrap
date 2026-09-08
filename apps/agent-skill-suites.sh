#!/bin/bash
# shellcheck disable=SC2034
# Workflow skill suites — superpowers, mattpocock/skills, gsd-pi and the
# context-engineering-kit — installed via the skills.sh CLI (npx skills)
# into ~/.agents/skills. Same roster format and mechanics as agent-skills
# (see lib/skills.sh); the split exists so the two sets can be selected
# independently.
#
# superpowers is installed for Codex only (-a codex; Codex reads the shared
# store directly, so no links are made anywhere): Claude Code gets it from
# the superpowers plugin (apps/claude-plugins.sh), whose SessionStart hook
# is what makes it fire automatically; a second copy under ~/.claude/skills
# would list every skill twice. mattpocock/skills replaced its plugin
# entirely (the plugin was skills-only, no hooks). "*" tracks the whole
# repo, so upstream additions and removals follow on the next update.
#
# The context-engineering-kit default is 22 of its 68 skills — the ones
# that add something the other suites lack; rationale in
# docs/superpowers/specs/2026-09-08-agent-skill-selection-design.md.
# Its test-driven-development and subagent-driven-development are left out
# deliberately: they collide by name with superpowers' in the flat store.
AGENT_SKILL_SUITES_UNIT="Agent skill suites"
APP_NAME="$AGENT_SKILL_SUITES_UNIT"
APP_CATEGORY="AI"

AGENT_SKILL_SUITES_ROSTER="obra/superpowers|codex|*
mattpocock/skills|*|*
open-gsd/gsd-pi|*|*
NeoLabHQ/context-engineering-kit|*|context-engineering prompt-engineering create-skill create-agent create-hook test-prompt test-skill agent-evaluation kaizen why cause-and-effect plan-do-check-act review-local-changes review-pr load-pr-comments design-testing-strategy test-coverage write-tests multi-agent-patterns judge reflect create-rule"

# Untracked leftovers to delete when the lock does not track the name:
# graphify (plain copied folder) and the 11 mattpocock skills upstream culled
# (their only copies were hand-synced; the user chose to drop them).
AGENT_SKILL_SUITES_PURGE="graphify caveman decision-mapping design-an-interface edit-article obsidian-vault qa request-refactor-plan review ubiquitous-language write-a-skill zoom-out"

agent_skill_suites_install()   { skills_unit_install   "$AGENT_SKILL_SUITES_UNIT" "$AGENT_SKILL_SUITES_ROSTER" "$AGENT_SKILL_SUITES_PURGE"; }
agent_skill_suites_update()    { skills_unit_update    "$AGENT_SKILL_SUITES_UNIT" "$AGENT_SKILL_SUITES_ROSTER" "$AGENT_SKILL_SUITES_PURGE"; }
agent_skill_suites_uninstall() { skills_unit_uninstall "$AGENT_SKILL_SUITES_UNIT" "$AGENT_SKILL_SUITES_ROSTER" "$1"; }
agent_skill_suites_installed() { skills_unit_installed "$AGENT_SKILL_SUITES_UNIT" "$AGENT_SKILL_SUITES_ROSTER"; }
