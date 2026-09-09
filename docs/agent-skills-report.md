# Agent skills: which ones pay off for this work

**Date:** 2026-09-08 · **Scope:** the skills this bootstrap installs (`apps/claude-plugins.sh`,
`apps/agent-skills.sh`, `apps/agent-skill-suites.sh`, selection in `~/.mac-bootstrap/skills.conf`)
ranked against the work actually done in 2026 across the `vindimy` repositories.

## How this was produced

- **Work sample.** The local clones and project folders under
  `~/Library/CloudStorage/Dropbox/Dev` were surveyed first (the `gh` CLI was not installed at
  the time). Five folders carry a `.git` directory with 2026 history; the rest were profiled
  from file dates and their `CLAUDE.md`. After `gh` was installed and authenticated the list
  was checked against GitHub: 19 of the 25 `vindimy` repositories were pushed in 2026, and all
  but one (`claude-great-cto`, empty, last push 2026-05-10) have a matching local folder. Only
  `claude-mac-bootstrap` and `claude-wa-agent` are public.
- **Skill catalogue.** 116 standalone skills in `~/.agents/skills` (source recorded in
  `~/.agents/.skill-lock.json`) plus the plugins in `~/.claude/settings.json`. Descriptions were
  read from each `SKILL.md`.
- **Ranking rule.** Score = how often the matching work shows up in 2026 × how much the skill
  changes speed or quality on that work × how ready it is (installed, enabled, fires on its own
  vs. needs an explicit call). Ties broken toward skills that guard quality on a direct-to-main
  workflow, which is how every repo here is run.

## What the 2026 work looks like

| Stream | Evidence | Share of effort |
|---|---|---|
| **A. Client and community websites** (Nyamaste Studios delivery) | `claude-veda-yoga` (73 commits, Apr–Sep), `claude-la-acro` (59, Jun–Sep), `claude-tracy-bryan-salon`, `claude-tempodozouk`, `claude-rock2o`, `claude-olya-dance`, `claude-zouk-socal`, `claude-dmitriy`, `claude-nyamaste-studios`. Single-page static HTML/CSS/JS, Cloudflare Workers via `wrangler.toml` + `deploy.sh` + `test.sh`, delivery standard in the wiki page `small-business-static-site`. Commits are dominated by content edits, image assets, layout fixes, SEO/analytics, schedule updates. | ~40% |
| **B. Running the business** (Nyamaste Studios LLC) | `claude-nyamaste-studios-strategy`: positioning and pricing (2026-07-19), contract/SOW/proposal/invoice/care-plan templates, client files, leads pipeline, ledger, legal compliance, founder-school learning records. Goal on record: first paying client under contract by 2026-10-19. | ~15% |
| **C. Software and agent engineering** | `claude-wa-agent` (TypeScript, 39 commits in six days, phased 1–12: Baileys listener, SQLite, scheduler, outbox gates, logging), `claude-zoukatoms-app` (student records platform: ~500 students, enrolment, certificates, payments), `claude-second-brain` (self-hosted AI deployment), `_wiki/llm-wiki`. | ~25% |
| **D. Machine and agent tooling** | this repo (75 commits since 2026-08-28: bash units, test harness, spec→plan→implement via `docs/superpowers/`, context-payload audit, skill curation). | ~15% |
| **E. Career and personal** | `claude-personal-branding` (strategic visibility as a Principal Cloud & DevOps Engineer in a large financial institution), `claude-olya-dima-finance` and `claude-olya-germany` (planning, still empty), community sites (la-acro, zouk-socal) that double as personal passions. | ~5% |

Cross-cutting habits that the ranking rewards: every repo is `CLAUDE.md`-first; Conventional
Commits; commits go straight to `main`; features are written as spec then plan before code;
long projects span many sessions; you already measure Claude Code's per-turn context cost.

## Ranking

### Tier 1: use by default, every session

These match the daily engineering loop across streams A, C and D. Most of them are already
firing (superpowers and context-mode are enabled plugins); the gain now is using them
consistently rather than installing anything new.

| # | Skill | Source | Why it ranks here | How to use |
|---|---|---|---|---|
| 1 | `brainstorming` → `writing-plans` → `executing-plans` / `subagent-driven-development` → `verification-before-completion` | obra/superpowers (plugin) | This is the workflow the bootstrap repo already runs (two specs and two plans in `docs/superpowers/`). It is what turned the skill-selection feature into a tested engine in one day. Same shape fits wa-agent phases and zoukatoms features. | Automatic via the SessionStart hook. Say "let's build X"; the brainstorm opens on its own. |
| 2 | `systematic-debugging` / `diagnosing-bugs` | superpowers / mattpocock | Fix commits are a steady share in every repo (bootstrap, wa-agent, site layout regressions). Both skills force reproduce → hypothesis → verify instead of guess-and-patch. | "diagnose this" or any bug report; superpowers triggers on its own. |
| 3 | `code-review` (since-a-point) + `review-local-changes` | mattpocock / context-engineering-kit | Direct-to-main means nobody reviews the diff before it ships. A pre-commit review pass on standards and on the originating spec is the only review these repos get. | `/code-review` on a range; `review-local-changes` before every commit of consequence. |
| 4 | `commit-work` | softaworks/agent-toolkit | Every repo uses Conventional Commits; the recent bootstrap history is a clean example. Splitting mixed changes into logical commits keeps the direct-to-main log readable. | "commit this" and let it stage and split. |
| 5 | `test-driven-development` + `design-testing-strategy` + `write-tests` | superpowers / context-engineering-kit | Bootstrap has a real harness (`tests/` with fakes and fixtures). wa-agent and zoukatoms are TypeScript with money and personal data in scope; tests are the only guard on a solo project. | TDD fires from superpowers; call `design-testing-strategy` once per project to fix the test shape, then `write-tests` to fill gaps. |
| 6 | `context-mode` (plugin) | mksglu/context-mode | You wrote a wiki page on Claude Code context bloat and run a payload audit on a cadence. This plugin is the operational answer: sandboxed execution and indexed recall keep raw output out of the window. | Enabled; it routes large outputs automatically. Use `ctx_search` on resume. |
| 7 | `writing-for-agents` + `agent-md-refactor` | mattpocock / softaworks | Every project is driven by a `CLAUDE.md`, and the client-site ones embed the whole design brief: 7,100 lines across the `claude-*` projects, with `claude-veda-yoga` and `claude-zoukatoms-app` each past 1,200. That is loaded on every turn. Progressive disclosure into `docs/` makes each session cheaper and more accurate. | Run `agent-md-refactor` once on each site repo's `CLAUDE.md`; use `writing-for-agents` when editing them afterwards. |
| 8 | `domain-modeling` + `grilling` / `grill-with-docs` | mattpocock | zoukatoms (students, levels, enrolment, certificates, payments, waitlists) and wa-agent (tenants, groups, outbox gates) are the two codebases where vocabulary drift costs the most. This repo already configured the single `CONTEXT.md` + `docs/adr/` convention that these skills write to. | Before a phase: "grill me on this design". Record outcomes as ADRs. |
| 9 | `handoff` / `session-handoff` / `claude-handoff` | mattpocock / softaworks | wa-agent went through twelve phases in six days; the bootstrap spec→plan cycle also crosses sessions. A handoff document beats re-reading history each morning. | "hand off" at the end of a session; `claude-handoff` to continue in the background. |
| 10 | `research` | mattpocock | Primary-source investigation saved as Markdown is exactly the `raw/` → `wiki/` pattern of your LLM wiki, and it is how the Google-Maps-scraping question in the salon project should have been settled. | "research X"; point the output at the wiki's `raw/`. |

### Tier 2: use at specific phases of a client or business engagement

Streams A and B. These are installed but only fire when named. Together they cover the
lifecycle of a Nyamaste Studios engagement: qualify → propose and contract → build → launch
and rank → retain on a care plan.

| # | Skill | Source | Fit | When |
|---|---|---|---|---|
| 11 | `contract-and-proposal-writer` | alirezarezvani | Goal 3 in the strategy repo is "no client work without a signature"; `templates/` already holds SOW, proposal, care-plan and invoice outlines. This skill produces jurisdiction-aware first drafts to reconcile with those templates. | Every new lead in `pipeline/LEADS.md`. |
| 12 | `copywriting` + `copy-editing` | coreyhaines31 | Hero, about, pricing and class-schedule copy is the bulk of the site commits. Copy that converts is also what the portfolio testimonials will be judged on. | New site: `copywriting`. Refresh (e.g. YTT cohort dates): `copy-editing`. |
| 13 | `local-seo-manager` | alirezarezvani | Every client is a location-bound LA service business (salon in Westwood, yoga studio with two locations, dance teachers). Google Business Profile, `LocalBusiness` schema, NAP consistency and review responses are exactly the care-plan deliverables you can charge for. | At launch and monthly under a care plan. |
| 14 | `seo-audit` + `ai-seo` | coreyhaines31 | Launch checklist and the answer to "why am I not ranking". `ai-seo` matters because prospects increasingly ask an assistant for "yoga studio near Culver City". | At launch; quarterly. |
| 15 | `frontend-design` (plugin) | anthropics | Site briefs are aesthetic-first ("warm, sensual, rhythmic", "premium men's grooming"). This plugin stops the output looking like a template. Enabled. | Any new page or redesign. |
| 16 | `cloudflare` (plugin) | cloudflare/skills | Every site deploys through `wrangler.toml`; the strategy inventory says it is "used for all Nyamaste client hosting". It had been left disabled; re-enabled in `dotfiles/.claude/settings.json` on 2026-09-08. | Any Worker, contact-form or DNS change; restart Claude Code once so the plugin loads. |
| 17 | `pricing` + `offers` | coreyhaines31 | `strategy/POSITIONING.md` sets prices; `offers` is the missing piece for packaging the care plan and site tiers with guarantees and bonuses so the first list-price sale closes. | Before the 2026-10-19 first-revenue milestone. |
| 18 | `customer-research` | coreyhaines31 | Testimonial collection from the three portfolio clients is a stated goal; the skill's interview and review-mining playbooks apply directly, and feed the niche positioning. | Now, with the three existing clients. |
| 19 | `document-skills` (docx/pdf/xlsx plugin) | anthropics/skills | Contracts, proposals and invoices leave the repo as PDF or Word files. Currently **disabled**. | Enable when producing client paperwork. |
| 20 | `wizard` | mattpocock | The bootstrap `docs/howto.md` is full of steps only a human can do (Little Snitch, Adobe sign-in, hardening toggles). A generated bash wizard turns those into a guided run. | Next time a manual-steps section grows. |
| 21 | `one-pager-prd` | lyndonkl | zoukatoms-app and wa-agent phases benefit from a one-page problem/users/metrics statement before the spec. | At the start of a new product or phase. |
| 22 | `crafting-effective-readmes` + `writing-clearly-and-concisely` | softaworks | Public-facing repos (wa-agent is written to be reusable, bootstrap is shared across machines). | When a README is created or drifts. |

### Tier 3: situational, worth keeping

| # | Skill | Source | Fit |
|---|---|---|---|
| 23 | `create-skill` + `test-skill` + `prompt-engineering` + `agent-evaluation` | context-engineering-kit | You curate skills as a bootstrap unit and audit their context cost. The highest-value use is to turn the wiki page `small-business-static-site` into a real skill so every client repo stops restating the delivery standard in `CLAUDE.md`. |
| 24 | `why` + `cause-and-effect` + `retro` | context-engineering-kit / mattpocock | Matches the founder-school learning-record habit ("scope trade under pressure", "recovery and client qualification"). Use after any engagement that went sideways. |
| 25 | `marketing-plan`, `marketing-ideas`, `content-strategy`, `social` | coreyhaines31 | Only once the first paying client exists. `social` also serves the personal-branding repo (LinkedIn visibility plan). |
| 26 | `writing-fragments` → `writing-beats` → `writing-shape` | mattpocock | The personal-branding repo asks for articles and talks; this trio is a good drafting pipeline for them. |
| 27 | `humanizer` (plugin) | blader | Client copy and LinkedIn posts. Disabled; enable when writing prose for humans. |
| 28 | `kaizen`, `reducing-entropy`, `improve-codebase-architecture`, `codebase-design` | context-engineering-kit / softaworks / mattpocock | Periodic cleanups of the bootstrap library and of wa-agent as it grows past its phases. |
| 29 | `setup-pre-commit`, `git-guardrails-claude-code`, `setup-ts-deep-modules` | mattpocock | One-time setup in the two TypeScript repos. Guardrails matter more than usual because agents push to `main`. |
| 30 | `founder-coach`, `cfo-advisor` | alirezarezvani | Founder-school notes exist; the CFO material is oversized for a single-member LLC but the cash-runway and unit-economics prompts are still useful once revenue starts. |
| 31 | `changelog-generator` | ComposioHQ | Turn site commit history into the monthly care-plan report for clients. |
| 32 | `to-spec`, `to-tickets`, `triage`, `wayfinder` | mattpocock | Only this repo tracks issues in GitHub, and `gh` is missing on the machine. Valuable once issue tracking is actually in use. |
| 33 | `requirements-clarity`, `feedback-mastery`, `professional-communication` | softaworks | Client intake conversations and difficult scope discussions. |

### Tier 4: installed but low fit, candidates to deselect

Deselecting is cheap (edit `~/.mac-bootstrap/skills.conf`, run `./update.sh`) and each
removed skill is one fewer entry in the per-turn skill listing the audit measures.

- `video`, `competitors` (vs-pages), `marketing-council`, `marketing-loops`,
  `marketing-psychology`, `site-architecture`, `competitor-profiling`, `competitive-intel`,
  `market-research`: SaaS-style marketing that does not match a local wellness web studio with
  a referral-driven niche.
- `brand-guidelines` (Anthropic's own palette), `canvas-design`, `artifacts-builder`
  (claude.ai artifacts): no matching work.
- `migrate-to-shoehorn`, `scaffold-exercises`, `teach`, `ask-matt`: course-authoring and
  TypeScript-migration tools with no matching project.
- `web-to-markdown` (manual-only), `meta-prompt-engineering` (overlaps
  `prompt-engineering`), `multi-agent-patterns`, `judge`, `reflect`, `plan-do-check-act`:
  overlapping or theoretical; keep at most one of each pair.

### Not installed, worth selecting

- `decision-matrix`, `expected-value`, `forecast-premortem`, `scout-mindset-bias-check`
  (lyndonkl/claude): the Germany-relocation and family-finance folders exist but are empty;
  these fit the planning stage they are in. They are roster defaults that this machine's
  selection dropped.
- `household-finance-dashboard-builder`, `pdf-statement-parser`, `transaction-categorizer`,
  `recurring-charge-detector`, `cash-flow-forecaster` (lyndonkl/claude): the business ledger
  is a Markdown file and the family finance repo is a placeholder; either can become real with
  these.

## Actions, in order of payoff

1. **Use Tier 1 on purpose.** The only new habit is running `review-local-changes` or
   `/code-review` before commits that touch behaviour, and `handoff` at the end of multi-day
   sessions.
2. ~~Enable the `cloudflare` plugin.~~ Done 2026-09-08 in `dotfiles/.claude/settings.json`.
3. **Refactor every project's `CLAUDE.md` with `agent-md-refactor`** (open, see Follow-ups),
   then package the `small-business-static-site` wiki page as a skill with `create-skill` so
   it is stated once.
4. **Run the engagement lifecycle skills** on the next lead: `contract-and-proposal-writer`
   → `copywriting` → `frontend-design` → `local-seo-manager` + `seo-audit` → `offers` for the
   care plan. This is the path to the 2026-10-19 first-revenue goal.
5. **Prune Tier 4** in `skills.conf` and **add the lyndonkl decision and finance skills**.
6. ~~Install `gh`.~~ Done 2026-09-08: new managed app unit `apps/gh.sh` (brew formula), added
   to this machine's selection and authenticated. The five triage labels from
   `docs/agents/triage-labels.md` now exist in the repo.

## Follow-ups

- [ ] **Refactor `CLAUDE.md` in every `claude-*` project with `agent-md-refactor`.** Tracked as
  [issue #1](https://github.com/vindimy/claude-mac-bootstrap/issues/1) (`needs-triage`).
  Order by size, largest first: `claude-veda-yoga` (1,292 lines),
  `claude-zoukatoms-app` (1,204), `claude-olya-dance` (722), `claude-second-brain` (643),
  `claude-nyamaste-studios` (642), `claude-tracy-bryan-salon` (546), `claude-la-acro` (385),
  then `claude-wa-agent`, `claude-rock2o`, `claude-tempodozouk`, `claude-zouk-socal`,
  `claude-dmitriy`, `claude-nyamaste-studios-strategy`, `claude-personal-branding`
  (`AGENTS.md`), and this repo. Acceptance: each root file holds only what an agent needs on
  every turn; briefs, history and reference material move under `docs/` and are linked from
  the root file; `writing-for-agents` is used for the rewrite; the site repos then point at
  the shared `small-business-static-site` standard instead of restating it.
