# Agent skills: which ones pay off for this work

**Date:** 2026-09-09 (rev 2) · **Scope:** every skill and plugin this bootstrap can install
(the rosters in `apps/claude-plugins.sh`, `apps/agent-skills.sh`, `apps/agent-skill-suites.sh`
and `apps/gsd.sh`), ranked against the 2026 work in the `vindimy` GitHub repositories and the
projects queued next.

## How this was produced

- **Work sample.** Pulled from GitHub with `gh`: every `vindimy` repository pushed in 2026,
  its commits since 2026-01-01, languages, issue count and visibility. Purpose and stack per
  project come from each repo's `CLAUDE.md`.
- **Skill catalogue.** Not what is selected on this machine but what the bootstrap offers: the
  ten skill repositories in the two skills rosters (listed live with the same helper
  `run.sh` uses), the eleven plugins in the plugin roster (read from the plugin cache), and
  the GSD suite. This machine currently has 116 of those skills selected and 3 of the 11
  plugins enabled.
- **Ranking rule.** Score = (how much of the 2026 work matches) + (how much of the queued
  work matches, weighted double) × (speed or quality gain) × (readiness: enabled and
  auto-firing, installed but needs a call, or not yet selected). Ties go to skills that guard
  quality on a direct-to-main, solo workflow.

## What the 2026 work looks like (GitHub, 2026-01-01 to 2026-09-09)

| Repo | Commits | Active | Issues | What it is |
|---|---|---|---|---|
| `claude-zoukatoms-app` | 498 | Jul–Aug | 14 | Student records platform for Zouk Atoms: ~500 students, levels, certificates, event registration and payments. TypeScript. |
| `claude-mac-bootstrap` | 78 | Aug–Sep | 1 | This repo. Bash units, test harness, skill curation, context audit. Public. |
| `claude-veda-yoga` | 72 | Apr–Sep | 1 | Non-profit yoga studio, two LA locations. Static site on Cloudflare. |
| `claude-la-acro` | 59 | Jun–Sep | 1 | LA AcroYoga community hub: jams, teachers, calendar, map. |
| `claude-olya-dance` | 41 | Feb–Jul | 12 | Olga Kostrova: Brazilian Zouk and Lambada teacher, Zouk Atoms co-creator, guest artist. |
| `claude-zouk-socal` | 40 | Feb–May | 0 | Southern California Zouk calendar. |
| `claude-wa-agent` | 39 | Sep | 6 | WhatsApp group digest agent: Baileys, SQLite, scheduler, outbox gates. TypeScript. Public. |
| `claude-rock2o` | 23 | Jul | 11 | Rock2O website rebuild and brand refresh. |
| `claude-tracy-bryan-salon` | 18 | Mar–Jul | 1 | Men's grooming salon, Westwood. Google Maps review scraping proved infeasible. |
| `claude-nyamaste-studios-strategy` | 14 | Jul–Aug | 0 | The LLC's business brain: positioning, pricing, templates, ledger, legal, pipeline, founder school. |
| `claude-dmitriy` | 10 | May | 0 | Personal portfolio site. |
| `claude-tempodozouk` | 9 | May–Jul | 0 | Zouk teaching duo site. |
| `llm-wiki` | 6 | May–Sep | 0 | Personal LLM-maintained wiki (Karpathy pattern); holds the site delivery standard. |
| `claude-second-brain` | 5 | Aug | 0 | Self-hosted personal AI, provisionable for family members. Docs only so far. |
| `claude-personal-branding` | 5 | Aug | 0 | Strategic visibility plan for a Principal Cloud and DevOps Engineer at a large financial institution. |
| `claude-nyamaste-studios` | 3 | May | 0 | The studio's own site. |
| `claude-olya-germany`, `claude-olya-dima-finance`, `claude-great-cto` | 1 each | May–Aug | 0 | Placeholders. |

Total: 923 commits in 19 repositories. By month: Feb 39, Mar 4, Apr 16, May 78, Jun 30,
Jul 427, Aug 226, Sep 103 so far. July and August were the Zouk Atoms build.

| Stream | Commits | Share |
|---|---|---|
| A. Software and agents (zoukatoms, wa-agent, second-brain, llm-wiki) | 548 | 59% |
| B. Client and community websites (nine static sites) | 275 | 30% |
| C. Machine and agent tooling (this repo) | 78 | 8% |
| D. Running the LLC (strategy repo) | 14 | 2% |
| E. Career and personal (branding, finance, relocation) | 8 | 1% |

Habits the ranking rewards: `CLAUDE.md`-first repos, Conventional Commits straight to
`main`, spec → plan → implement, GitHub issues in the four largest projects, a measured
per-turn context budget.

## What is queued next

Stated on 2026-09-09, and weighted double in the ranking:

1. **SEO for Veda Yoga and Tracy Bryan's Salon.** Two location-bound LA service businesses
   already hosted on Cloudflare.
2. **Full marketing strategy and execution for Olya.** Dance teacher and partner; the
   `claude-olya-dance` site and the Zouk Atoms platform are the assets; audience is students,
   festival organisers and the international Zouk community.
3. **Second brain.** Agents that take over more of personal day-to-day life, on own hardware.
4. **Growing Nyamaste Studios LLC.** First paying client at list price is the open goal.

Marketing was 0% of 2026 commits and is three of the four next projects. The catalogue has a
deep marketing bench (50 skills in coreyhaines31, 30 more in alirezarezvani, a marketing
cluster in ecc) of which 18 are selected. That gap drives most of the changes below.

## Ranking

Tier 1 is what the next three projects need. Tier 2 is the engineering loop that produced
59% of the year's commits and continues under the second brain and Zouk Atoms. Tier 3 is
the second brain specifically. Tier 4 is the LLC. Tier 5 is what to drop.

### Tier 1: marketing and SEO execution kit

| # | Skill | Source | Status | Why |
|---|---|---|---|---|
| 1 | `seo-audit` + `schema` | coreyhaines31 | selected / **add** | The Veda and Tracy engagements start with an audit; `schema` writes the `LocalBusiness`, `Event`, `Course` and `FAQ` structured data those sites lack. Both already have the pages, only the markup is missing. |
| 2 | `local-seo-manager` | alirezarezvani | selected | Google Business Profile, NAP consistency, review responses, neighbourhood service pages. This is the deliverable both clients can be billed for monthly. |
| 3 | `ai-seo` / `aeo` | coreyhaines31 / alirezarezvani | selected / add one | "Yoga studio near Culver City" is now asked to an assistant as often as to Google. Keep `ai-seo`; `aeo` overlaps it, add only if its checklist differs on a test run. |
| 4 | `analytics` + `analytics-tracking` | coreyhaines31 / alirezarezvani | **add both** | GA4 exists on the sites (la-acro commit 2026-07-06) but no event taxonomy or conversion tracking. Without it neither SEO engagement can prove results. |
| 5 | `cro` + `form-cro` | coreyhaines31 / alirezarezvani | **add** | Booking and contact forms are the conversion point on every site; `signup` is SaaS-shaped and stays out. |
| 6 | `web-perf` | cloudflare plugin | plugin enabled | Core Web Vitals and Lighthouse on Workers-hosted sites. Fits the SEO audits directly. |
| 7 | `marketing-context` + `marketing-ops` | alirezarezvani | **add** | One context document that every marketing skill reads first, and a router. This is how the Olya engagement stays coherent across sessions instead of re-briefing each skill. |
| 8 | `marketing-plan` → `product-marketing` → `offers` → `pricing` | coreyhaines31 | selected / **add product-marketing** | Olya's strategy: positioning (guest artist vs. local teacher vs. online), the offer ladder (drop-in, series, privates, festival bookings, online course), pricing per tier. `positioning` lives inside `product-marketing`. |
| 9 | `customer-research` | coreyhaines31 | selected | Interviews with current students and festival organisers before any copy. Also produces the testimonials the LLC needs. |
| 10 | `content-strategy` + `content-production` | coreyhaines31 / alirezarezvani | selected / **add** | Olya's calendar: class series, festival appearances, technique explainers. `content-production` takes a topic to publish-ready. |
| 11 | `social` + `social-media-manager` + `social-content` + `social-media-analyzer` | coreyhaines31 / alirezarezvani | selected / **add three** | Instagram is the dance world's channel. Strategy, calendar, per-post copy, and engagement measurement are four different jobs. |
| 12 | `video` + `video-content-strategist` | coreyhaines31 / alirezarezvani | selected / **add** | Dance sells on video. Reels and YouTube technique clips; `yt-dlp` and `ffmpeg` are now managed apps. |
| 13 | `emails` + `email-sequence` + `lead-magnets` + `popups` | coreyhaines31 / alirezarezvani | **add** | A mailing list is the one asset Olya owns that no platform can take away. Lead magnet (free technique guide), capture, welcome and workshop-announcement sequences. |
| 14 | `events` + `webinar-marketing` + `launch` | coreyhaines31 / alirezarezvani | **add** | Workshops, festival bookings, an online course launch, and Veda's online Gita class are all events with a promotion cycle. |
| 15 | `community-marketing` + `influencer-marketing` + `co-marketing` + `referrals` | coreyhaines31 | **add** | Zouk is a community; referrals and collaborations with organisers and other artists are the growth loop, per the LLC's own positioning doc. |
| 16 | `copywriting` + `copy-editing` + `content-humanizer` / `humanizer` | coreyhaines31 / alirezarezvani / plugin | selected / add one | Every page and post. Pick one humanizer; the plugin is disabled today. |
| 17 | `brand-guidelines` | alirezarezvani | **add** | The real one (the ComposioHQ skill of the same name applies Anthropic's palette). Olya and Rock2O both need a written brand. |
| 18 | `competitive-ads-extractor` + `competitor-profiling` | ComposioHQ / coreyhaines31 | add / selected | What other dance teachers and studios run in the Meta ad library. Cheap research before Olya's first paid campaign. |
| 19 | `ads` + `ad-creative` | coreyhaines31 | add later | Only once organic and email are running; small budgets for workshop fills. |
| 20 | `image` | coreyhaines31 | **add** | Social graphics and blog heroes at volume. |

### Tier 2: the engineering loop (already proven, keep firing)

| # | Skill | Source | Why |
|---|---|---|---|
| 21 | `brainstorming` → `writing-plans` → `executing-plans` / `subagent-driven-development` → `verification-before-completion` | superpowers | Produced this repo's specs and plans and fits the second brain's phased build. Fires from the SessionStart hook. |
| 22 | `systematic-debugging` / `diagnosing-bugs` | superpowers / mattpocock | Zouk Atoms carries payments and personal data; wa-agent runs unattended. |
| 23 | `code-review` + `review-local-changes` + `commit-work` | mattpocock / CEK / softaworks | The only review a direct-to-main repo gets. |
| 24 | `test-driven-development` + `design-testing-strategy` + `write-tests` | superpowers / CEK | Tests exist here; extend the habit to the TypeScript repos. |
| 25 | `domain-modeling` + `grilling` / `grill-with-docs` | mattpocock | Zouk Atoms vocabulary (levels, completions, waitlists) and the second brain's data model. Writes the `CONTEXT.md` and ADRs this repo already configured. |
| 26 | `writing-for-agents` + `agent-md-refactor` | mattpocock / softaworks | Tracked as [issue #1](https://github.com/vindimy/claude-mac-bootstrap/issues/1): 7,100 lines of `CLAUDE.md` across projects, loaded every turn. |
| 27 | `context-mode` (plugin) + `strategic-compact` / `config-gc` (ecc) | enabled / not enabled | Context cost is measured on a cadence here; these are the operational levers. |
| 28 | `handoff` / `session-handoff` / `claude-handoff` | mattpocock / softaworks | Multi-day builds (Zouk Atoms, wa-agent phases). |
| 29 | `research` + `deep-research` (ecc) | mattpocock / ecc | Primary-source notes into the wiki's `raw/`. |
| 30 | `wizard` | mattpocock | Human-only steps in `docs/howto.md` and in the second brain's hardware setup. |
| 31 | `cloudflare` plugin: `wrangler`, `workers-best-practices`, `cloudflare-email-service`, `turnstile-spin` | enabled since 2026-09-08 | Every site deploys through it; email sending and bot-safe forms are the next two features clients ask for. |
| 32 | `to-spec` / `to-tickets` / `triage` / `oh-my-issues` | mattpocock / claude-mem | Issues and PRs are live in four repos (47 across all); `gh` is now installed and authenticated. |

### Tier 3: second brain and personal automation

| # | Skill | Source | Status | Why |
|---|---|---|---|---|
| 33 | `agents-sdk` + `durable-objects` | cloudflare plugin | enabled | The natural runtime for always-on personal agents with state, alongside the self-hosted box. |
| 34 | `autonomous-agent-harness` + `continuous-agent-loop` + `autonomous-loops` | ecc | plugin disabled | Scheduled operations, task queues, quality gates and recovery for unattended agents. This is the architecture reading for the second brain before code. |
| 35 | `email-ops`, `messages-ops`, `google-workspace-ops`, `unified-notifications-ops` | ecc | plugin disabled | Inbox triage, messaging, Drive/Sheets, notifications: the day-to-day surfaces the second brain is meant to take over. |
| 36 | `inbox-setup` + `inbox-triage` + `weekly-review` + `meetings` | alirezarezvani | **add** | Personal operating rhythm: a triage knowledge base built once, a weekly review that closes loops. Lightweight, no plugin needed. |
| 37 | `connect` / `connect-apps` (Composio) + `composio` | ComposioHQ / composiohq | add / selected | Take real actions in Gmail, Calendar, Slack, GitHub from an agent. The action layer under the second brain. |
| 38 | `claude-mem` plugin: `mem-search`, `weekly-digests`, `knowledge-agent`, `standup` | thedotmack | plugin disabled | Persistent cross-session memory and digests. Overlaps context-mode's session memory; enable it in the second-brain repo only and compare before going global. |
| 39 | `memory-engineering` + `agent-memory` + `unified-memory` (ecc) | alirezarezvani / ecc | **add** / disabled | Designing the memory layer is the second brain's central decision. |
| 40 | `file-organizer`, `invoice-organizer`, `meeting-insights-analyzer`, `image-enhancer` | ComposioHQ | **add** | Concrete chores to automate first: files, receipts for the LLC ledger, meeting notes. |
| 41 | `household-finance-dashboard-builder`, `pdf-statement-parser`, `transaction-categorizer`, `recurring-charge-detector`, `cash-flow-forecaster` | lyndonkl | **add** | The family finance repo is a placeholder; this set turns bank statements into a dashboard with no SaaS. |
| 42 | `decision-matrix`, `expected-value`, `forecast-premortem`, `scout-mindset-bias-check` | lyndonkl | **add** | The Germany decision and any relocation or money choice. Roster defaults this machine dropped. |
| 43 | `agent-launcher-orchestrator` + `fable-goal` | alirezarezvani | add later | Claude Managed Agents as a hosted alternative for scheduled personal jobs. |
| 44 | `understand-knowledge` | understand-anything plugin | disabled | Graph view of the LLM wiki once it has more than a handful of pages. |
| 45 | `create-skill` + `test-skill` + `prompt-engineering` + `agent-evaluation` | CEK | selected | Each second-brain automation becomes a skill; test it before it runs unattended. |

### Tier 4: running and growing the LLC

| # | Skill | Source | Status | Why |
|---|---|---|---|---|
| 46 | `contract-and-proposal-writer` | alirezarezvani | selected | No client work without a signature; templates exist, this drafts the instance. |
| 47 | `offers` + `pricing` + `pricing-strategist` | coreyhaines31 / alirezarezvani | selected / add | Package the care plan and SEO retainer so the first list-price sale closes. |
| 48 | `lead-research-assistant` + `prospecting` + `cold-email` | ComposioHQ / coreyhaines31 | add | The pipeline file has leads; the niche is wellness and movement businesses in LA. Warm referral first, cold second. |
| 49 | `document-skills` plugin (`docx`, `pdf`, `xlsx`) | anthropics | disabled | Contracts and invoices leave the repo as files. |
| 50 | `changelog-generator` | ComposioHQ | selected | Monthly care-plan report from site commits. |
| 51 | `founder-coach`, `cfo-advisor`, `founder-mode`, `cmo-review` / `cfo-review` | alirezarezvani | selected / add two | Founder-school learning records exist; the C-suite review skills interrogate a plan before money moves. |
| 52 | `linkedin-content` + `writing-fragments` → `writing-beats` → `writing-shape` | alirezarezvani / mattpocock | add / selected | Personal-branding repo: the visibility plan needs posts and one long piece. |
| 53 | `retro`, `why`, `cause-and-effect`, `reviews-retros-reflection` | mattpocock / CEK / lyndonkl | selected / add | After each engagement, feed founder-school records. |

### Tier 5: selected today with no matching work

Deselect in `~/.mac-bootstrap/skills.conf`, then `./update.sh`. Each one is an entry in the
per-turn skills catalogue the audit measures.

- `competitors`, `marketing-council`, `marketing-loops`, `marketing-psychology`,
  `site-architecture`, `competitive-intel`, `market-research`: SaaS-shaped or duplicated by
  the additions above.
- `brand-guidelines` (ComposioHQ, Anthropic's palette), `canvas-design`, `artifacts-builder`.
- `migrate-to-shoehorn`, `scaffold-exercises`, `teach`, `ask-matt`, `setup-matt-pocock-skills`.
- `web-to-markdown`, `meta-prompt-engineering`, `multi-agent-patterns`, `judge`, `reflect`,
  `plan-do-check-act`: overlapping; keep at most one of each pair.

## Selection changes, as `skills.conf` lines

The lines below are the complete new values; the rosters already carry every name.

```
SKILLS_coreyhaines31__marketingskills="seo-audit schema ai-seo analytics cro marketing-plan product-marketing offers pricing customer-research content-strategy social video emails lead-magnets popups events launch community-marketing influencer-marketing co-marketing referrals copywriting copy-editing competitor-profiling image marketing-ideas prospecting cold-email"
SKILLS_alirezarezvani__claude_skills="local-seo-manager analytics-tracking form-cro marketing-context marketing-ops content-production social-media-manager social-content social-media-analyzer video-content-strategist email-sequence webinar-marketing brand-guidelines content-humanizer pricing-strategist contract-and-proposal-writer founder-coach cfo-advisor founder-mode cmo-review cfo-review inbox-setup inbox-triage weekly-review meetings memory-engineering agent-memory linkedin-content"
SKILLS_lyndonkl__claude="one-pager-prd decision-matrix expected-value forecast-premortem scout-mindset-bias-check household-finance-dashboard-builder pdf-statement-parser transaction-categorizer recurring-charge-detector cash-flow-forecaster reviews-retros-reflection"
SKILLS_ComposioHQ__awesome_claude_skills="changelog-generator content-research-writer competitive-ads-extractor connect connect-apps file-organizer invoice-organizer meeting-insights-analyzer image-enhancer lead-research-assistant youtube-downloader"
SKILLS_NeoLabHQ__context_engineering_kit="agent-evaluation cause-and-effect context-engineering create-agent create-hook create-rule create-skill design-testing-strategy kaizen load-pr-comments prompt-engineering review-local-changes review-pr test-coverage test-prompt test-skill why write-tests"
```

`softaworks`, `mattpocock`, `superpowers`, `gsd-pi` and `composiohq` are unchanged. Net
effect on the store: roughly +45 marketing, personal-ops and finance skills, −15 unused ones.

### Applied 2026-09-09: audit delta

The lines above were written to `~/.mac-bootstrap/skills.conf` (previous file kept as
`skills.conf.pre-2026-09-09.bak`) and `./update.sh` ran clean. The store went from 116 to
160 skills; the lock file attributes exactly the selected names to each source.

`claude-context-audit.sh` before and after (headless probe, global config only):

| | Tools | Tool bytes | Input tokens | Skills listed | With description | Name only |
|---|---|---|---|---|---|---|
| Before | 13 | 28,498 | 28,957 | 91 | 83 | 8 |
| After | 13 | 28,498 | 28,969 | 134 | 62 | 72 |

The token count is flat because Claude Code caps the skills section: every skill is listed
by name, but descriptions are added only while a budget of about 30 KB lasts (29.7 KB before,
29.4 KB after). Adding 44 skills therefore cost no tokens and instead **stripped the
description from 72 skills**, which is what the model uses to decide when to invoke one. Among
the name-only set after the change: `seo-audit`, `schema`, `social`, `marketing-plan`,
`marketing-context`, `offers`, `pricing`, `product-marketing`, `video`,
`review-local-changes`, `test-prompt`, `write-tests`, every `cloudflare:*` skill,
`frontend-design`, and `superpowers:verification-before-completion`,
`superpowers:requesting-code-review`, `superpowers:using-git-worktrees`. Explicit `/name`
invocation still works for all of them; automatic triggering does not.

Two ways to get the descriptions back, both reversible:

1. **Hide the explicit-only skills from the model.** The managed `skillOverrides` map in
   `dotfiles/.claude/settings.json` already marks 147 skills `user-invocable-only`, which drops
   them from the listing entirely. Most of the additions are things you would call by name
   anyway (`inbox-setup`, `weekly-review`, the five household-finance skills, the four
   decision skills, `youtube-downloader`, `file-organizer`, `invoice-organizer`,
   `image-enhancer`, `meeting-insights-analyzer`, `competitive-ads-extractor`,
   `lead-research-assistant`, `cfo-review`, `cmo-review`, `founder-mode`, `linkedin-content`,
   `webinar-marketing`, `events`, `launch`, `popups`, `lead-magnets`, `influencer-marketing`,
   `co-marketing`, `community-marketing`, `referrals`, `prospecting`, `cold-email`, `image`,
   `social-media-analyzer`, `memory-engineering`, `agent-memory`, `meetings`,
   `reviews-retros-reflection`). Marking those frees roughly 20 KB, enough for the
   auto-trigger skills to keep their descriptions.
2. **Move the Olya-only marketing set out of the global store** and install it per project
   in that repo (`npx skills add <repo> -s ...` without `-g`), so its descriptions are loaded
   only where they apply.

Option 1 is the smaller change and keeps one place of truth; option 2 is the right shape
long-term for engagement-specific kits. Neither has been applied yet.

Plugins (in `dotfiles/.claude/settings.json`): keep `superpowers`, `frontend-design`,
`context-mode`, `cloudflare` on. Enable `humanizer` and `document-skills` when the Olya
copy and the LLC paperwork start. Do **not** enable `ecc` globally: it ships 288 English
skills plus translations and would dominate the per-turn payload. Enable it per project in
the second-brain repo's `.claude/settings.json`, or run its own `agent-sort` skill once to get
a trimmed install plan. Same per-project treatment for `claude-mem`.

## Actions, in order of payoff

1. ~~Apply the `skills.conf` changes above and run `./update.sh`.~~ Done 2026-09-09; delta
   recorded above. **Open decision:** restore descriptions for the auto-trigger skills via
   `skillOverrides` (option 1) or per-project installs (option 2).
2. **Start the SEO engagements with the audit chain:** `seo-audit` → `schema` →
   `local-seo-manager` → `analytics` + `analytics-tracking` → `web-perf` → `cro`. Same
   sequence for Veda and Tracy; the second run is mostly reuse.
3. **Open the Olya engagement with `marketing-context`,** then `customer-research`,
   `product-marketing`, `marketing-plan`, `offers`. Execution skills (social, video, emails,
   events) only after the plan names the channels.
4. **Second brain: read before building.** `autonomous-agent-harness`,
   `continuous-agent-loop`, `memory-engineering`, then `domain-modeling` and an ADR on the
   memory layer. First automations: `inbox-triage`, `weekly-review`, `invoice-organizer`,
   `file-organizer`, each packaged with `create-skill` and checked with `test-skill`.
5. **LLC:** `offers` for the SEO retainer and care plan, `contract-and-proposal-writer` for
   the first signed engagement, `document-skills` on for the paperwork.
6. **Engineering loop:** unchanged, plus `review-local-changes` before behaviour-changing
   commits and `handoff` at the end of multi-day sessions.
7. ~~Enable the `cloudflare` plugin.~~ Done 2026-09-08. ~~Install `gh`.~~ Done 2026-09-08,
   authenticated 2026-09-09; triage labels created.

## Follow-ups

- [ ] **Refactor `CLAUDE.md` in every `claude-*` project with `agent-md-refactor`.** Tracked as
  [issue #1](https://github.com/vindimy/claude-mac-bootstrap/issues/1) (`needs-triage`).
  Largest first: `claude-veda-yoga` (1,292 lines), `claude-zoukatoms-app` (1,204),
  `claude-olya-dance` (722), `claude-second-brain` (643), `claude-nyamaste-studios` (642),
  `claude-tracy-bryan-salon` (546), `claude-la-acro` (385), then the rest and this repo.
  Acceptance: each root file holds only what an agent needs on every turn; briefs and
  reference material move under `docs/`; the site repos point at the shared
  `small-business-static-site` standard instead of restating it.
- [ ] **Package `small-business-static-site` as a skill** with `create-skill` once the
  refactor lands.
- [x] **Apply the selection changes** (action 1). Done 2026-09-09; delta recorded under
  "Applied 2026-09-09: audit delta".
- [ ] **Restore skill descriptions** for the auto-trigger set: extend `skillOverrides` in
  `dotfiles/.claude/settings.json` (option 1) or move the marketing kit to per-project
  installs (option 2), then re-run the audit and confirm `seo-audit`, `schema`,
  `marketing-plan`, `cloudflare:*` and the superpowers skills list with descriptions again.
