# Agent Skill Selection Design

**Status: approved 2026-09-08, not yet implemented.** Supersedes the
"deliberately not managed" stance recorded in the header of
`apps/agent-skills.sh` and in README/howto.

## Goal

Manage every standalone agent skill on the machine from upstream, and let the
user choose per repo which skills are installed and kept updated:

- Add a second skills unit, **Agent skill suites**, for the workflow suites
  obra/superpowers, mattpocock/skills, open-gsd/gsd-pi and
  NeoLabHQ/context-engineering-kit.
- Give both skills units an interactive per-repo checklist so the installed
  set is a saved, per-machine selection rather than a hard-coded roster.
- Remove `graphify` (a plain copied folder with no upstream tracking) and stop
  carrying hand-copied duplicates of skills that upstream now publishes.
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
  overwrites it in place, so "update" can simply be "add again".
- `-s '*'` installs every skill in a repo; `-a <agents>` restricts which
  agent directories receive links; `-l` lists a repo's skills with their
  descriptions without installing.
- The superpowers plugin ships a SessionStart hook that injects
  `using-superpowers`; plain skills in the store have no hooks. The
  mattpocock-skills plugin has no hooks, commands or agents — only skills.
- On this machine the store holds exactly the 30 softaworks skills. The 20
  mattpocock copies, 19 awesome-claude-skills copies and graphify described in
  the 2026-08-27 inventory are absent here (the "sync manually" step never
  happened), which is the failure this design removes.

## Decisions

| Question | Decision |
|---|---|
| mattpocock-skills plugin vs skills unit | Skills unit replaces the plugin. Drop it from `apps/claude-plugins.sh`; uninstall the plugin once on this machine. |
| superpowers plugin vs skills unit | Keep the plugin (its hook). The skills unit installs superpowers into the store linked **only into Codex**, so Claude Code never sees duplicates. |
| context-engineering-kit scope | Curated default subset of 22 (below); user can change it in the checklist. |
| Existing five-repo unit | Gets the same per-repo selection; its current roster becomes its defaults. |
| When to prompt | First install: always (interactive). Later runs: one `[y/N]` per unit, default no. Never in `update.sh` or `--non-interactive`. |
| Culled mattpocock skills (11 names not upstream) | Out of scope; left untouched wherever they exist. |
| awesome-claude-skills copies | Out of scope; docs stop describing them as present. |

## Architecture

### `lib/skills.sh` — shared engine

Sourced after `lib/common.sh` (and `lib/ui.sh` when interactive). Units hold
only a roster and delegate:

```sh
skills_unit_install   <unit-id> "$ROSTER"          # first-time: select, then reconcile
skills_unit_update    <unit-id> "$ROSTER"          # optional reselect, then reconcile
skills_unit_uninstall <unit-id> "$ROSTER" keep|zap
skills_unit_installed <unit-id> "$ROSTER"
```

**Roster format** — one record per line, three `|`-separated fields:

```
owner/repo|agents|default-skills
```

- `agents`: `*` (every detected agent) or a space-separated agent list
  (e.g. `codex`), passed to `skills add -a`.
- `default-skills`: space-separated names, or `*` meaning every skill the
  repo publishes at selection time.

**Internal pieces** (all private to the module):

| Function | Role |
|---|---|
| `skills_list_upstream <repo>` | Runs `npx -y skills add <repo> -l`, parses name + first description line. Prints `name<TAB>description` lines. On parse failure prints names only; on network failure returns 1. Cached per process. |
| `skills_lock_names <repo>` | Names in `~/.agents/.skill-lock.json` whose `source` equals `<repo>` (python3 JSON read; the file may be absent). |
| `skills_select_repo <repo> <current> <defaults>` | Interactive checklist for one repo (see UI). Prints the chosen names. |
| `skills_reconcile <repo> <agents> <selected>` | `add` for `selected` (refreshes in place); `remove -g -y` for `lock − selected`. Skips with a log line when `agents` names an agent whose skills dir is missing. |
| `skills_conf_get/put <repo>` | Read/write one variable in `skills.conf`. |

**npm/npx dependency** — reuse the existing pattern: install the `node`
formula if `npx` is missing.

### Selection flow

```
install
  ├─ saved selection exists (e.g. after a keep-uninstall) → same as update
  ├─ interactive?  → per-repo checklist, pre-checked with roster defaults
  └─ else          → roster defaults (`*` = full upstream list)
  save → reconcile

update
  ├─ no saved selection → same as install
  ├─ interactive? → "Reselect skills for <unit>? [y/N]"  (Enter = no)
  │     └─ y → per-repo checklist pre-checked with saved selection
  └─ save (if changed) → reconcile
```

"Interactive" means `${NON_INTERACTIVE:-1}` is `0` and `lib/ui.sh` is loaded
(same test `lib/drivers.sh` already uses). `update.sh` never sets
`NON_INTERACTIVE=0`, so it never prompts.

### UI — `select_from_list` in `lib/ui.sh`

Generic multi-select used by the engine; `select_apps` is left as is.

```
Agent skill suites — NeoLabHQ/context-engineering-kit (68 upstream)
   1) [x] context-engineering   Understand the components, mechanics, and constr…
   2) [ ] add-task              creates draft task file in .specs/tasks/draft/ …
   3) [ ] actualize    (new)    Reconcile the project's FPF state with recent …
  ...
Toggle numbers (space-separated), a=all, n=none, Enter=confirm:
```

- Items are the live upstream list, so skills removed upstream vanish from the
  checklist; if one was saved it is dropped from the selection with a warning.
- `(new)` marks names not present in the previous saved selection **and** not
  in the defaults — only shown when a saved selection exists.
- Descriptions are truncated to the terminal width; names only if the parse
  produced no descriptions.
- Same input grammar as the app checklist; invalid tokens warn and re-prompt.

### Persistence — `~/.mac-bootstrap/skills.conf`

Shell-sourced like `apps.conf`, written whole on every save:

```sh
# Managed by run.sh — per-machine agent skill selection (one line per repo).
SKILLS_obra__superpowers="brainstorming systematic-debugging ..."
SKILLS_mattpocock__skills="..."
```

Variable name = `SKILLS_` + repo with `/` → `__` and any other non
`[A-Za-z0-9_]` character → `_`. A repo with an empty selection keeps its line
with an empty value (it is "selected, nothing chosen", distinct from absent).
Roster defaults never overwrite a saved line.

### Reconciliation and state

The CLI lock file is the installed-state oracle; nothing is stored twice.

| Operation | Behaviour |
|---|---|
| install / update | per repo: `skills add <repo> -g -y -a <agents> -s <selected>` (skipped when selected is empty); then `skills remove -g -y <lock − selected>` (skipped when empty). Failures are logged per repo; the unit returns non-zero if any repo failed. |
| uninstall keep | `skills remove -g -y` of every lock name sourced from the unit's repos. `skills.conf` untouched. |
| uninstall zap | keep, plus delete the unit's lines from `skills.conf`. |
| installed | every roster repo has a line in `skills.conf` **and** every selected name exists as `~/.agents/skills/<name>`. No line → not installed. |

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

**Graphify:** the suites unit's install removes `~/.agents/skills/graphify`
and `~/.claude/skills/graphify` if present (guarded `rm -rf`; both are
untracked copies with no lock entry).

### Units

**`apps/agent-skills.sh`** — renamed "Agent skills (curated task packs)".
`APP_NOTE` removed; header rewritten. Roster (defaults = today's lists):

```
softaworks/agent-toolkit|*|agent-md-refactor ... writing-clearly-and-concisely   (30)
composiohq/skills|*|composio
coreyhaines31/marketingskills|*|seo-audit ai-seo schema cro analytics ab-testing copywriting content-strategy customer-research pricing
lyndonkl/claude|*|household-finance-dashboard-builder ... focus-timeboxing-8020  (10)
alirezarezvani/claude-skills|*|founder-coach cfo-advisor contract-and-proposal-writer local-seo-manager competitive-intel market-research
```

**`apps/agent-skill-suites.sh`** — "Agent skill suites", category AI:

```
obra/superpowers|codex|*
mattpocock/skills|*|*
open-gsd/gsd-pi|*|*
NeoLabHQ/context-engineering-kit|*|context-engineering prompt-engineering create-skill create-agent create-hook test-prompt test-skill agent-evaluation kaizen why cause-and-effect plan-do-check-act review-local-changes review-pr load-pr-comments design-testing-strategy test-coverage write-tests multi-agent-patterns judge reflect create-rule
```

The context-engineering-kit default deliberately excludes its copies of
`test-driven-development`, `subagent-driven-development`, `git-worktrees`,
`root-cause-tracing` and `brainstorm`: the store is flat, and the first two
would collide by name with superpowers' skills.

**`apps/claude-plugins.sh`** — remove `mattpocock-skills@claude-plugins-official`
from `CLAUDE_PLUGINS` (roster count 12 → 11). One-time on this machine:
`claude plugin uninstall mattpocock-skills@claude-plugins-official`.

### Error handling

- Upstream listing fails (offline): install with no saved selection falls
  back to roster defaults if they are explicit names, otherwise errors out
  for that repo; update with a saved selection reconciles without prompting.
- `python3` missing: lock-file read fails → the engine treats lock names as
  empty (no removals) and warns; installs still work. (python3 ships with
  the Xcode CLT that run.sh already requires.)
- Per-repo failures never abort the other repos of the unit.

### Docs

- README: rename the `agent-skills` row, add an `agent-skill-suites` row,
  update `claude-plugins` count, rewrite the agent-tooling paragraph
  (selection, `skills.conf`, no local-only set).
- `docs/howto.md`: replace the `agent-skills` section with one covering both
  units, reselection, `skills.conf`, and the one-time mattpocock plugin
  uninstall. Drop the bare-update warning.
- `claude-nyamaste-studios-strategy/tech/skills.md` (other repo) is out of
  scope but should be updated to match.

## Testing

Automated where the repo allows (no test harness exists; shellcheck is the
gate), manual for the rest:

1. `shellcheck lib/skills.sh lib/ui.sh apps/agent-skills.sh apps/agent-skill-suites.sh apps/claude-plugins.sh`.
2. `./run.sh --dry-run --non-interactive` and `./update.sh --dry-run` show the
   expected `skills add/remove` commands and no prompts.
3. Live first install of `agent-skill-suites` via `./run.sh`: four checklists
   appear with the right defaults; `skills.conf` is written; store contains
   the selected names; superpowers links exist only under `~/.codex/skills`;
   `graphify` absent; `claude plugin list` no longer shows mattpocock-skills.
4. Reselect via `./run.sh` → `y`: uncheck one skill and check one new skill;
   verify the removal and the addition in the store and lock file.
5. `./update.sh`: no prompt; refreshes selected skills; `installed` returns 0.
6. Deselect the unit in `./run.sh` (keep): every skill sourced from the four
   repos is gone from the store and lock; softaworks skills untouched;
   `skills.conf` still has the lines. Re-selecting the unit reinstalls the
   saved selection: interactively it asks the `[y/N]` (Enter reinstalls as
   saved), non-interactively it reinstalls as saved with no prompt.
7. `agent-skills` (existing unit): update path shows the `[y/N]` prompt,
   Enter skips, store unchanged.
