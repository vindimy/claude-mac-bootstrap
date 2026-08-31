#!/bin/bash
# shellcheck disable=SC2034
# Standalone agent skills — provenance-tracked, upstream-restorable sets
# installed globally via the skills.sh CLI (npx skills), which links them
# into all configured agents. Managed as a roster of repo|skill-list records
# (AGENT_SKILLS_SETS below): to manage more skills, extend a record's list
# or add a new "owner/repo|name name ..." line — nothing else to register.
#
# DELIBERATELY NOT MANAGED (cannot be rebuilt from upstream; live only in the
# local ~/.agents/skills store): the 20 mattpocock skills (upstream culled
# them — a bulk `skills update` would sync the deletions and destroy the only
# surviving copies), the 19 awesome-claude-skills copies, and graphify.
# Never run a bare `npx skills update` here — updates are selective by name.
#
# Roster sources: softaworks + composio from the 2026-08-27 audit in
# claude-nyamaste-studios-strategy/tech/skills.md; marketing (coreyhaines31),
# personal-finance/decision (lyndonkl), and business-ops (alirezarezvani)
# subsets curated 2026-08-30 — each repo carries hundreds more skills, listed
# via `npx skills add <owner/repo> -l`; keep installs selective to avoid
# skill-list bloat in every agent session.
APP_NAME="Agent skills (provenance-tracked)"
APP_NOTE="Local-only skills (mattpocock set, awesome-claude-skills copies, graphify) are not managed here — sync those manually."

# One record per line: owner/repo|space-separated skill names.
# The FIRST skill of each record doubles as that repo's installed-sentinel.
AGENT_SKILLS_SETS="softaworks/agent-toolkit|agent-md-refactor backend-to-frontend-handoff-docs c4-architecture codex command-creator commit-work crafting-effective-readmes database-schema-designer dependency-updater design-system-starter difficult-workplace-conversations draw-io feedback-mastery frontend-to-backend-requirements game-changing-features gemini gepetto lesson-learned mui naming-analyzer perplexity plugin-forge professional-communication qa-test-planner reducing-entropy requirements-clarity session-handoff ship-learn-next skill-judge writing-clearly-and-concisely
composiohq/skills|composio
coreyhaines31/marketingskills|seo-audit ai-seo schema cro analytics ab-testing copywriting content-strategy customer-research pricing
lyndonkl/claude|household-finance-dashboard-builder pdf-statement-parser transaction-categorizer recurring-charge-detector cash-flow-forecaster decision-matrix forecast-premortem expected-value scout-mindset-bias-check focus-timeboxing-8020
alirezarezvani/claude-skills|founder-coach cfo-advisor contract-and-proposal-writer local-seo-manager competitive-intel market-research"

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

# All roster skill names as one space-separated list.
agent_skills_all_names() {
  local repo skills
  while IFS='|' read -r repo skills; do
    if [ -n "$repo" ]; then printf '%s ' "$skills"; fi
  done <<<"$AGENT_SKILLS_SETS"
}

agent_skills_install() {
  local repo skills csv rc=0
  if ! agent_skills_require_npm; then return 1; fi
  while IFS='|' read -r repo skills; do
    if [ -z "$repo" ]; then continue; fi
    csv="$(printf '%s' "$skills" | tr ' ' ',')"
    if ! run_cmd npx -y skills add "$repo" -g -y -s "$csv"; then
      err "agent-skills: install from $repo failed"
      rc=1
    fi
  done <<<"$AGENT_SKILLS_SETS"
  return "$rc"
}

# Selective update by name — NEVER a bare `skills update` (see header).
agent_skills_update() {
  if ! agent_skills_require_npm; then return 1; fi
  if ! agent_skills_installed && [ "$DRY_RUN" != 1 ]; then
    agent_skills_install
    return
  fi
  # shellcheck disable=SC2046
  run_cmd npx -y skills update -g -y $(agent_skills_all_names)
}

# Removes only the roster names; local-only skills are never touched.
# $1 (keep|zap) is ignored: skills have no separate settings to zap.
agent_skills_uninstall() {
  if ! agent_skills_require_npm; then return 1; fi
  # shellcheck disable=SC2046
  run_cmd npx -y skills remove -g -y $(agent_skills_all_names)
}

# Installed when every record's sentinel (its first skill) is present.
agent_skills_installed() {
  local repo skills first
  while IFS='|' read -r repo skills; do
    if [ -z "$repo" ]; then continue; fi
    first="${skills%% *}"
    if [ ! -d "$HOME/.claude/skills/$first" ]; then return 1; fi
  done <<<"$AGENT_SKILLS_SETS"
}
