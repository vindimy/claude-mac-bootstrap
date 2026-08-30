#!/bin/bash
# shellcheck disable=SC2034
# Standalone agent skills — ONLY the provenance-tracked, upstream-restorable
# set from claude-nyamaste-studios-strategy/tech/skills.md (2026-08-27 audit):
# softaworks/agent-toolkit (30) + composio (composiohq/skills), installed
# globally via the skills.sh CLI (npx skills) which links them into all
# configured agents.
#
# DELIBERATELY NOT MANAGED (cannot be rebuilt from upstream; live only in the
# local ~/.agents/skills store): the 20 mattpocock skills (upstream culled
# them — a bulk `skills update` would sync the deletions and destroy the only
# surviving copies), the 19 awesome-claude-skills copies, and graphify.
# Never run a bare `npx skills update` here — updates are selective by name.
APP_NAME="Agent skills (provenance-tracked)"
APP_NOTE="Local-only skills (mattpocock set, awesome-claude-skills copies, graphify) are not managed here — sync those manually."

AGENT_SKILLS_TOOLKIT_REPO="softaworks/agent-toolkit"
AGENT_SKILLS_TOOLKIT="agent-md-refactor backend-to-frontend-handoff-docs c4-architecture codex command-creator commit-work crafting-effective-readmes database-schema-designer dependency-updater design-system-starter difficult-workplace-conversations draw-io feedback-mastery frontend-to-backend-requirements game-changing-features gemini gepetto lesson-learned mui naming-analyzer perplexity plugin-forge professional-communication qa-test-planner reducing-entropy requirements-clarity session-handoff ship-learn-next skill-judge writing-clearly-and-concisely"
AGENT_SKILLS_COMPOSIO_REPO="composiohq/skills"
AGENT_SKILLS_COMPOSIO="composio"

agent_skills_require_npm() {
  if ! command -v npx >/dev/null 2>&1; then
    log "npx not found — installing Node.js first"
    formula_install node
  fi
  if ! command -v npx >/dev/null 2>&1 && [ "$DRY_RUN" != 1 ]; then
    err "npx still not available — install Node.js and retry"
    return 1
  fi
}

agent_skills_install() {
  local toolkit_csv
  if ! agent_skills_require_npm; then return 1; fi
  toolkit_csv="$(printf '%s' "$AGENT_SKILLS_TOOLKIT" | tr ' ' ',')"
  if ! run_cmd npx -y skills add "$AGENT_SKILLS_TOOLKIT_REPO" -g -y -s "$toolkit_csv"; then
    err "agent-skills: install from $AGENT_SKILLS_TOOLKIT_REPO failed"
    return 1
  fi
  run_cmd npx -y skills add "$AGENT_SKILLS_COMPOSIO_REPO" -g -y -s "$AGENT_SKILLS_COMPOSIO"
}

# Selective update by name — NEVER a bare `skills update` (see header).
agent_skills_update() {
  if ! agent_skills_require_npm; then return 1; fi
  if ! agent_skills_installed && [ "$DRY_RUN" != 1 ]; then
    agent_skills_install
    return
  fi
  # shellcheck disable=SC2086
  run_cmd npx -y skills update -g -y $AGENT_SKILLS_TOOLKIT $AGENT_SKILLS_COMPOSIO
}

# Removes only the managed names; local-only skills are never touched.
# $1 (keep|zap) is ignored: skills have no separate settings to zap.
agent_skills_uninstall() {
  if ! agent_skills_require_npm; then return 1; fi
  # shellcheck disable=SC2086
  run_cmd npx -y skills remove -g -y $AGENT_SKILLS_TOOLKIT $AGENT_SKILLS_COMPOSIO
}

# Sentinel check: one skill from each managed repo.
agent_skills_installed() {
  [ -d "$HOME/.claude/skills/commit-work" ] && [ -d "$HOME/.claude/skills/composio" ]
}
