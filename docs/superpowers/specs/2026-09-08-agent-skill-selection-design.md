# Agent Skill Selection Design

**Status: approved 2026-09-08 (rev 2), not yet implemented.** Supersedes the
"deliberately not managed" stance recorded in the header of
`apps/agent-skills.sh` and in README/howto. Rev 2 adds: awesome-claude-skills
managed from its upstream, removal of the culled mattpocock copies, the
"track all" (`*`) selection semantic, and the rationale sections.

## Goal

Manage every standalone agent skill on the machine from upstream, and let the
user choose per repo which skills are installed and kept updated:

- Add a second skills unit, **Agent skill suites**, for the workflow suites
  obra/superpowers, mattpocock/skills, open-gsd/gsd-pi and
  NeoLabHQ/context-engineering-kit.
- Give both skills units an interactive per-repo checklist so the installed
  set is a saved, per-machine selection rather than a hard-coded roster.
- Replace the hand-copied awesome-claude-skills set with an upstream-managed
  install from ComposioHQ/awesome-claude-skills.
- Remove the untracked leftovers: `graphify`, the 11 culled mattpocock
  copies, and the renamed `video-downloader` copy.
- Retire the "local-only skills are synced manually" note and the warning
  against a bare `skills update`; after this change nothing in the shared
  store is untracked.

## Background

The skills.sh CLI (`npx skills`) installs skills into the shared store
`~/.agents/skills/<name>/`, links them into every detected agent
(`~/.claude/skills`, `~/.codex/skills`, ...), and records provenance in
`~/.agents/.skill-lock.json` with a `source` (`owner/repo`) per skill.

Verified 2026-09-08:

- `skills add <repo> -g -y -s <names>` re-run on an already installed skill
  overwrites it in place from the repo's current default branch, so "update"
  can simply be "add again".
- `-s '*'` installs every skill in a repo; `-a <agents>` restricts which
  agent directories receive links; `-l` lists a repo's skills with their
  descriptions without installing.
- The superpowers plugin ships a SessionStart hook that injects
  `using-superpowers`; plain skills in the store have no hooks. The
  mattpocock-skills plugin has no hooks, commands or agents — only skills.
- `ComposioHQ/awesome-claude-skills` publishes 28 skills through the CLI,
  including 18 of the 19 names that were hand-copied in the 2026-08-27
  inventory; the 19th, `video-downloader`, is now `youtube-downloader`.
- On this machine the store holds exactly the 30 softaworks skills. The 20
  mattpocock copies, 19 awesome-claude-skills copies and graphify described in
  the inventory are absent here (the "sync manually" step never happened),
  which is the failure this design removes.

## Decisions

| Question | Decision |
|---|---|
| mattpocock-skills plugin vs skills unit | Skills unit replaces the plugin. Drop it from `apps/claude-plugins.sh`; uninstall the plugin once on this machine. See "Keeping mattpocock/skills updated". |
| superpowers plugin vs skills unit | Keep the plugin (its hook). The skills unit installs superpowers into the store linked **only into Codex**, so Claude Code never sees duplicates. |
| context-engineering-kit scope | Curated default subset of 22; the checklist lets the user pick any other subset at install or reselect. See "How the subset was chosen". |
| Existing five-repo unit | Gets the same per-repo selection; its current roster becomes its defaults; gains a sixth repo, ComposioHQ/awesome-claude-skills. |
| awesome-claude-skills local copies | Replaced: the 18 surviving names are reinstalled from upstream (overwritten in place); the renamed `video-downloader` copy is purged. |
| Culled mattpocock skills (11 names not upstream) | Purged wherever an untracked copy exists. |
| When to prompt | First install: always (interactive). Later runs: one `[y/N]` per unit, default no. Never in `update.sh` or `--non-interactive`. |
| Upstream additions | A selection saved as `*` tracks the whole repo, so new upstream skills install on the next update. An explicit name list never grows on its own. |

## Keeping mattpocock/skills updated without the plugin

Both mechanisms pull from the same GitHub repo; they differ in cadence and
version pinning:

| | Plugin (`claude plugin update`) | Skills unit (`update.sh`) |
|---|---|---|
| Source | marketplace entry pointing at github.com/mattpocock/skills, pinned to a released version (1.2.3 today) | the repo's default branch at the moment of the update |
| Trigger | `apps/claude-plugins.sh` update step in `update.sh` | `apps/agent-skill-suites.sh` update step in `update.sh` — same run |
| New upstream skills | arrive with the next release | arrive on the next update when the selection is `*`; otherwise appear as `(new)` in the next reselect |
| Skills removed upstream | disappear with the next release | removed from the store on the next update when the selection is `*` (lock names not in the upstream list); with an explicit list they stay until deselected |
| Agents served | Claude Code only | every detected agent (Claude Code, Codex, ...) |

So nothing is lost on freshness: `update.sh` already runs every selected unit,
and the suites unit re-runs `skills add mattpocock/skills -s ...`, which
overwrites each selected skill from upstream HEAD. The one trade-off is that
the plugin followed tagged releases while the skills CLI follows the branch
head, which is slightly fresher and slightly less curated. The default
selection for mattpocock/skills is `*`, so it keeps tracking the whole repo.

## How the context-engineering-kit subset was chosen

The kit publishes 68 skills; the store is flat and every installed skill is
listed in every agent session, so the default keeps only what adds something
the other suites do not. The default is only the pre-checked state of the
checklist — any other subset can be chosen at first install, and changed later
via reselect. Exclusion rules, in order:

1. **Name collisions** with skills already in the store from superpowers:
   `test-driven-development`, `subagent-driven-development`. A flat store
   cannot hold two skills with one name.
2. **Near-duplicates** of superpowers/mattpocock skills:
   `brainstorm`, `git-worktrees`, `root-cause-tracing`, `write-concisely`
   (softaworks has `writing-clearly-and-concisely`), `commit`
   (softaworks `commit-work`).
3. **Skills bound to the kit's own project layout** (FPF state, `.specs/`
   task files): `actualize`, `add-task`, `plan-task`, `implement-task`,
   `propose-hypotheses`, `query`, `status`, `reset`, `decay`, `load-issues`,
   `analyze-issue`, `update-docs`, `create-workflow-command`.
4. **Setup guides for specific third-party tools**: `setup-arxiv-mcp`,
   `setup-codemap-cli`, `setup-context7-mcp`, `setup-serena-mcp`,
   `build-mcp` (Anthropic's `mcp-builder` is already installed via the
   example-skills plugin).
5. **Heavy multi-agent orchestrators** that overlap superpowers'
   dispatching/subagent workflow: `do-in-parallel`, `do-in-steps`,
   `do-competitively`, `do-and-judge`, `tree-of-thoughts`,
   `judge-with-debate`, `critique`, `launch-sub-agent`,
   `thought-based-reasoning`, `create-ideas`.
6. **GitHub plumbing already covered by `gh` habits**: `create-pr`,
   `attach-review-to-pr`, `resolve-fixed-pr-comments`, `git-notes`,
   `traiage-review`.
7. **Superseded or narrower variants of kept skills**: `fix-tests`
   (`write-tests` + TDD), `create-command` (Claude Code commands are being
   folded into skills), `apply-anthropic-skill-best-practices` (folded into
   `create-skill`), `analyse` and `analyse-problem` (auto-pickers over the
   kept `kaizen`/`why`/`cause-and-effect`), `memorize` (writes to CLAUDE.md
   on its own; `create-rule` is the deliberate version).

The seven rules exclude 46 skills (2 + 5 + 13 + 5 + 10 + 5 + 6), leaving the
22 below.

What remains, grouped by what it is for:

- Agent building (8): `context-engineering`, `prompt-engineering`,
  `create-skill`, `create-agent`, `create-hook`, `test-prompt`,
  `test-skill`, `agent-evaluation`
- Kaizen (4): `kaizen`, `why`, `cause-and-effect`, `plan-do-check-act`
- Review (3): `review-local-changes`, `review-pr`, `load-pr-comments`
- Testing (3): `design-testing-strategy`, `test-coverage`, `write-tests`
- Orchestration and reflection (4): `multi-agent-patterns`, `judge`,
  `reflect`, `create-rule`

This is a judgment call, not a measurement; the checklist exists so it does
not have to be right for everyone.

## Architecture

### `lib/skills.sh` — shared engine

Sourced after `lib/common.sh` (and `lib/ui.sh` when interactive). Units hold
only a roster, an optional purge list, and delegate:

```sh
skills_unit_install   <unit-id> "$ROSTER" "$PURGE"   # select (or reuse), purge, reconcile
skills_unit_update    <unit-id> "$ROSTER" "$PURGE"   # optional reselect, purge, reconcile
skills_unit_uninstall <unit-id> "$ROSTER" keep|zap
skills_unit_installed <unit-id> "$ROSTER"
```

**Roster format** — one record per line, three `|`-separated fields:

```
owner/repo|agents|default-skills
```

- `agents`: `*` (every detected agent) or a space-separated agent list
  (e.g. `codex`), passed to `skills add -a`.
- `default-skills`: space-separated names, or `*` meaning "track every skill
  the repo publishes, now and later".

**Purge list** — space-separated store names that are known untracked
leftovers. A name is deleted from `~/.agents/skills/<name>` and every agent
link dir only when it has **no** entry in the lock file; a tracked skill of
the same name is never touched.

**Internal pieces** (all private to the module):

| Function | Role |
|---|---|
| `skills_list_upstream <repo>` | Runs `npx -y skills add <repo> -l`, parses name + first description line. Prints `name<TAB>description` lines. On parse failure prints names only; on network failure returns 1. Cached per process. |
| `skills_lock_names <repo>` | Names in `~/.agents/.skill-lock.json` whose `source` equals `<repo>` (python3 JSON read; the file may be absent). |
| `skills_select_repo <repo> <current> <defaults>` | Interactive checklist for one repo (see UI). Prints the chosen names, or `*` when every listed skill ended up checked. |
| `skills_reconcile <repo> <agents> <selected>` | `add` for `selected` (refreshes in place); `remove -g -y` for `lock − selected`. When `selected` is `*`, adds with `-s '*'` and removes `lock − upstream list`. Skips with a log line when `agents` names an agent whose skills dir is missing. |
| `skills_purge_untracked <names>` | The purge rule above. |
| `skills_conf_get/put <repo>` | Read/write one variable in `skills.conf`. |

**npm/npx dependency** — reuse the existing pattern: install the `node`
formula if `npx` is missing.

### Selection flow

```
install
  ├─ saved selection exists (e.g. after a keep-uninstall) → same as update
  ├─ interactive?  → per-repo checklist, pre-checked with roster defaults
  └─ else          → roster defaults (`*` stays `*`)
  save → purge → reconcile

update
  ├─ no saved selection → same as install
  ├─ interactive? → "Reselect skills for <unit>? [y/N]"  (Enter = no)
  │     └─ y → per-repo checklist pre-checked with saved selection
  └─ save (if changed) → purge → reconcile
```

"Interactive" means `${NON_INTERACTIVE:-1}` is `0` and `lib/ui.sh` is loaded
(same test `lib/drivers.sh` already uses). `update.sh` never sets
`NON_INTERACTIVE=0`, so it never prompts.

### UI — `select_from_list` in `lib/ui.sh`

Generic multi-select used by the engine; `select_apps` is left as is.

```
Agent skill suites — NeoLabHQ/context-engineering-kit (68 upstream, 22 selected)
   1) [x] context-engineering   Understand the components, mechanics, and constr…
   2) [ ] add-task              creates draft task file in .specs/tasks/draft/ …
   3) [ ] actualize    (new)    Reconcile the project's FPF state with recent …
  ...
Toggle numbers (space-separated), a=all, n=none, Enter=confirm:
```

- Items are the live upstream list, so skills removed upstream vanish from the
  checklist; if one was saved it is dropped from the selection with a warning.
- A saved or default `*` pre-checks everything. Confirming with every item
  checked saves `*` ("track all"); unchecking anything saves an explicit
  list. The header line says which one will be saved.
- `(new)` marks names not present in the previous saved selection — only
  shown when a saved explicit list exists.
- Descriptions are truncated to the terminal width; names only if the parse
  produced no descriptions.
- Same input grammar as the app checklist; invalid tokens warn and re-prompt.

### Persistence — `~/.mac-bootstrap/skills.conf`

Shell-sourced like `apps.conf`, written whole on every save:

```sh
# Managed by run.sh — per-machine agent skill selection (one line per repo;
# "*" = track every skill the repo publishes).
SKILLS_obra__superpowers="*"
SKILLS_mattpocock__skills="*"
SKILLS_NeoLabHQ__context_engineering_kit="context-engineering prompt-engineering ..."
```

Variable name = `SKILLS_` + repo with `/` → `__` and any other non
`[A-Za-z0-9_]` character → `_`. A repo with an empty selection keeps its line
with an empty value (it is "selected, nothing chosen", distinct from absent).
Roster defaults never overwrite a saved line.

### Reconciliation and state

The CLI lock file is the installed-state oracle; nothing is stored twice.

| Operation | Behaviour |
|---|---|
| install / update | purge list first. Then per repo: `skills add <repo> -g -y -a <agents> -s <selected or '*'>` (skipped when selected is empty); then `skills remove -g -y <stale>` where stale = `lock − selected`, or `lock − upstream list` when selected is `*` (skipped when empty). Failures are logged per repo; the unit returns non-zero if any repo failed. |
| uninstall keep | `skills remove -g -y` of every lock name sourced from the unit's repos. `skills.conf` untouched. |
| uninstall zap | keep, plus delete the unit's lines from `skills.conf`. |
| installed | every roster repo has a line in `skills.conf` **and** every selected name exists as `~/.agents/skills/<name>` (for `*`: at least one lock entry with that source). No line → not installed. |

`remove` is always fed explicit names derived from the lock file for the
unit's own repos; the engine never issues a bare `skills update` or
`skills remove --all`, so skills from other sources (or the other unit) are
never touched.

**Agents restriction:** for a record whose `agents` is not `*`, each named
agent must have its skills dir (`~/.codex/skills` for `codex`). If missing,
the record is skipped with a log line and does not count as a failure — on a
fresh machine `agent-skill-suites` sorts before `codex`, so the first run.sh
pass skips superpowers for Codex and the next `update.sh` installs it.
`installed` treats a skipped record as satisfied only when its dir is still
missing.

### Units

**`apps/agent-skills.sh`** — renamed "Agent skills (curated task packs)".
`APP_NOTE` removed; header rewritten. Roster (defaults = today's lists plus
the awesome-claude-skills set):

```
softaworks/agent-toolkit|*|agent-md-refactor ... writing-clearly-and-concisely   (30)
composiohq/skills|*|composio
coreyhaines31/marketingskills|*|seo-audit ai-seo schema cro analytics ab-testing copywriting content-strategy customer-research pricing
lyndonkl/claude|*|household-finance-dashboard-builder ... focus-timeboxing-8020  (10)
alirezarezvani/claude-skills|*|founder-coach cfo-advisor contract-and-proposal-writer local-seo-manager competitive-intel market-research
ComposioHQ/awesome-claude-skills|*|changelog-generator competitive-ads-extractor connect connect-apps content-research-writer developer-growth-analysis domain-name-brainstormer file-organizer image-enhancer invoice-organizer langsmith-fetch lead-research-assistant meeting-insights-analyzer raffle-winner-picker skill-share tailored-resume-generator template-skill twitter-algorithm-optimizer youtube-downloader
```

The awesome-claude-skills default is the 19 names that were hand-copied
(with `youtube-downloader` for the renamed `video-downloader`). Its other nine
skills are Anthropic's examples (`artifacts-builder`, `brand-guidelines`,
`canvas-design`, `internal-comms`, `mcp-builder`, `skill-creator`,
`slack-gif-creator`, `theme-factory`, `webapp-testing`), already installed by
the `example-skills` plugin, so they stay unchecked by default.

Purge list: `video-downloader`.

**`apps/agent-skill-suites.sh`** — "Agent skill suites", category AI:

```
obra/superpowers|codex|*
mattpocock/skills|*|*
open-gsd/gsd-pi|*|*
NeoLabHQ/context-engineering-kit|*|context-engineering prompt-engineering create-skill create-agent create-hook test-prompt test-skill agent-evaluation kaizen why cause-and-effect plan-do-check-act review-local-changes review-pr load-pr-comments design-testing-strategy test-coverage write-tests multi-agent-patterns judge reflect create-rule
```

Purge list: `graphify` plus the 11 mattpocock names upstream no longer
publishes: `caveman decision-mapping design-an-interface edit-article
obsidian-vault qa request-refactor-plan review ubiquitous-language
write-a-skill zoom-out`.
The 9 still-published names (`claude-handoff loop-me writing-beats
writing-fragments writing-shape git-guardrails-claude-code migrate-to-shoehorn
scaffold-exercises setup-pre-commit`) need no purge: `skills add` overwrites
the untracked copy in place and the lock gains the entry.

**`apps/claude-plugins.sh`** — remove `mattpocock-skills@claude-plugins-official`
from `CLAUDE_PLUGINS` (roster count 12 → 11). One-time on this machine:
`claude plugin uninstall mattpocock-skills@claude-plugins-official`.

### Error handling

- Upstream listing fails (offline): install with no saved selection falls
  back to roster defaults (explicit names install as given; `*` installs
  with `-s '*'` and skips the stale-removal step); update with a saved
  selection reconciles without prompting, likewise skipping stale removal
  for `*` repos.
- `python3` missing: lock-file read fails → the engine treats lock names as
  empty (no removals, no purges) and warns; installs still work. (python3
  ships with the Xcode CLT that run.sh already requires.)
- Per-repo failures never abort the other repos of the unit.

### Docs

- README: rename the `agent-skills` row (6 repos), add an
  `agent-skill-suites` row, update `claude-plugins` count, rewrite the
  agent-tooling paragraph (selection, `*` tracking, `skills.conf`, no
  local-only set).
- `docs/howto.md`: replace the `agent-skills` section with one covering both
  units, reselection, `skills.conf`, `*` vs explicit lists, and the one-time
  mattpocock plugin uninstall. Drop the bare-update warning.
- `claude-nyamaste-studios-strategy/tech/skills.md` (other repo) is out of
  scope but should be updated to match.

## Testing

No test harness exists; shellcheck is the gate, the rest is a scripted manual
pass on this machine:

1. `shellcheck lib/skills.sh lib/ui.sh apps/agent-skills.sh apps/agent-skill-suites.sh apps/claude-plugins.sh`.
2. `./run.sh --dry-run --non-interactive` and `./update.sh --dry-run` show the
   expected purge, `skills add` and `skills remove` commands and no prompts.
3. Live first install of `agent-skill-suites` via `./run.sh`: four checklists
   appear with the right defaults; `skills.conf` has `*` for superpowers,
   mattpocock and gsd-pi and the 22 names for the kit; store contains the
   selected names; superpowers links exist only under `~/.codex/skills`;
   `graphify` absent; `claude plugin list` no longer shows mattpocock-skills.
4. Purge: plant an untracked `~/.agents/skills/caveman` and
   `~/.claude/skills/video-downloader`, run `./update.sh`, confirm both are
   gone and a tracked skill of a purge-listed name (none expected) would be
   left alone (unit test of `skills_purge_untracked` with a fake lock).
5. Reselect via `./run.sh` → `y`: uncheck one kit skill and check one new
   one; verify the removal and the addition in the store and lock. Then for
   mattpocock uncheck one skill: `skills.conf` switches from `*` to an
   explicit list; re-check it: back to `*`.
6. `./update.sh`: no prompt; refreshes selected skills; `installed` returns 0.
7. `agent-skills` (existing unit) update: awesome-claude-skills installs
   its 19 defaults; the `[y/N]` prompt appears, Enter skips.
8. Deselect the suites unit in `./run.sh` (keep): every skill sourced from
   the four repos is gone from the store and lock; softaworks and
   awesome-claude-skills untouched; `skills.conf` still has the lines.
   Re-selecting reinstalls the saved selection (interactive: `[y/N]` first).
