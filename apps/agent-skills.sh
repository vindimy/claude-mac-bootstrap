#!/bin/bash
# shellcheck disable=SC2034
# Curated task-pack skills — installed globally via the skills.sh CLI (npx
# skills) into ~/.agents/skills and linked into every configured agent.
# One roster record per upstream repo: owner/repo|agents|default-skills.
# agents "*" = every agent lib/skills.sh knows that is installed on this
# machine (SKILLS_KNOWN_AGENTS), passed explicitly as -a.
# The defaults are only the pre-checked state of the per-repo checklist that
# run.sh shows on first install (and on "Reselect skills?"); the machine's
# actual selection lives in ~/.mac-bootstrap/skills.conf. Mechanics are in
# lib/skills.sh — this file is data.
#
# Defaults: softaworks + composio from the 2026-08-27 audit; marketing
# (coreyhaines31), personal-finance/decision (lyndonkl) and business-ops
# (alirezarezvani) subsets curated 2026-08-30; awesome-claude-skills
# (ComposioHQ) = the 19 skills that used to be hand-copied, with
# youtube-downloader for the renamed video-downloader (2026-09-08). The rest
# of that repo is Anthropic's example skills, already installed by the
# example-skills plugin. Each repo carries more — see them in the checklist.
AGENT_SKILLS_UNIT="Agent skills (curated task packs)"
APP_NAME="$AGENT_SKILLS_UNIT"
APP_CATEGORY="AI"

AGENT_SKILLS_ROSTER="softaworks/agent-toolkit|*|agent-md-refactor backend-to-frontend-handoff-docs c4-architecture codex command-creator commit-work crafting-effective-readmes database-schema-designer dependency-updater design-system-starter difficult-workplace-conversations draw-io feedback-mastery frontend-to-backend-requirements game-changing-features gemini gepetto lesson-learned mui naming-analyzer perplexity plugin-forge professional-communication qa-test-planner reducing-entropy requirements-clarity session-handoff ship-learn-next skill-judge writing-clearly-and-concisely
composiohq/skills|*|composio
coreyhaines31/marketingskills|*|seo-audit ai-seo schema cro analytics ab-testing copywriting content-strategy customer-research pricing
lyndonkl/claude|*|household-finance-dashboard-builder pdf-statement-parser transaction-categorizer recurring-charge-detector cash-flow-forecaster decision-matrix forecast-premortem expected-value scout-mindset-bias-check focus-timeboxing-8020
alirezarezvani/claude-skills|*|founder-coach cfo-advisor contract-and-proposal-writer local-seo-manager competitive-intel market-research
ComposioHQ/awesome-claude-skills|*|changelog-generator competitive-ads-extractor connect connect-apps content-research-writer developer-growth-analysis domain-name-brainstormer file-organizer image-enhancer invoice-organizer langsmith-fetch lead-research-assistant meeting-insights-analyzer raffle-winner-picker skill-share tailored-resume-generator template-skill twitter-algorithm-optimizer youtube-downloader"

# Untracked hand-copied leftovers to delete (only when the lock does not
# track the name): the pre-rename awesome-claude-skills copy.
AGENT_SKILLS_PURGE="video-downloader"

agent_skills_install()   { skills_unit_install   "$AGENT_SKILLS_UNIT" "$AGENT_SKILLS_ROSTER" "$AGENT_SKILLS_PURGE"; }
agent_skills_update()    { skills_unit_update    "$AGENT_SKILLS_UNIT" "$AGENT_SKILLS_ROSTER" "$AGENT_SKILLS_PURGE"; }
agent_skills_uninstall() { skills_unit_uninstall "$AGENT_SKILLS_UNIT" "$AGENT_SKILLS_ROSTER" "$1"; }
agent_skills_installed() { skills_unit_installed "$AGENT_SKILLS_UNIT" "$AGENT_SKILLS_ROSTER"; }
