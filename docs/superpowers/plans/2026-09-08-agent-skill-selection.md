# Agent Skill Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage every standalone agent skill from upstream through two roster-based units with a per-repo interactive checklist, a saved per-machine selection, and lock-file-driven reconciliation.

**Architecture:** A new shared engine `lib/skills.sh` owns everything about the skills.sh CLI (listing, install, removal, lock file, saved selection, purge). Units (`apps/agent-skills.sh`, new `apps/agent-skill-suites.sh`) are a roster string plus four one-line delegations. A generic `select_from_list` checklist joins `lib/ui.sh`. A tiny bash test harness with a fake `npx` on PATH makes the engine testable offline.

**Tech Stack:** bash 3.2 (macOS stock `/bin/bash`), python3 (ships with Xcode CLT) for JSON and text parsing, skills.sh CLI via `npx -y skills`, shellcheck.

**Spec:** `docs/superpowers/specs/2026-09-08-agent-skill-selection-design.md`

## Global Constraints

- **bash 3.2 compatible.** No `mapfile`/`readarray`, no associative arrays, no `${var,,}`, no `;&`. Arrays are fine; guard empty-array expansion with `${arr[@]+"${arr[@]}"}`. Test with `/bin/bash`.
- **Every mutating command goes through `run_cmd`** (from `lib/common.sh`) so `--dry-run` prints it instead.
- **Never** issue a bare `npx skills update`, `skills remove --all`, or `skills remove` without explicit names derived from the lock file for the unit's own repos.
- **No `log` (stdout) inside any function whose stdout is captured with `$(...)`** — use `warn`/`printf >&2`. Violations silently corrupt the selection.
- **Unit files must not reference `$APP_NAME` inside functions.** `discover_apps` resets `APP_NAME` before sourcing each app, so at call time it holds the *last* app's name. Store the unit name in a unit-specific variable.
- A literal `*` selection must be passed to the CLI quoted (`-s '*'`); an unquoted `$selected` would glob.
- Roster iteration must not consume stdin (the checklist reads it). Use `skills_roster_record` (line N via `sed -n`), never `while read <<<"$ROSTER"` around code that prompts.
- Conventional Commits; commit after every task.
- Paths: store `~/.agents/skills`, lock `~/.agents/.skill-lock.json`, config `$CONFIG_DIR/skills.conf` (`CONFIG_DIR` from `lib/common.sh`, overridable via `BOOTSTRAP_CONFIG_DIR`).
- Roster record: `owner/repo|agents|default-skills`; `agents` is `*` or names like `codex`; `default-skills` is space-separated names or `*`.

---

## File map

| File | Responsibility |
|---|---|
| `tests/run.sh` | Runs every `tests/test_*.sh` with `/bin/bash`; non-zero if any fails |
| `tests/lib.sh` | Assertions, sandbox (`setup_sandbox`), lib loader |
| `tests/fakes/npx` | Fake skills.sh CLI: renders `-l` from fixtures, simulates `add`/`remove` against the sandbox store and lock, logs every call |
| `tests/fixtures/repo-*.txt` | `name<TAB>description` per line, per fake repo |
| `tests/fixtures/real-list-gsd-pi.txt` | Raw capture of the real CLI's `-l` output (ANSI included) for the parser test |
| `lib/skills.sh` | The engine (conf, listing, lock, agents, purge, reconcile, unit ops) |
| `lib/ui.sh` | `+ select_from_list` |
| `run.sh`, `update.sh` | source `lib/skills.sh` after `lib/drivers.sh` |
| `apps/agent-skills.sh` | Rewritten as roster + delegations, renamed, sixth repo |
| `apps/agent-skill-suites.sh` | New unit |
| `apps/claude-plugins.sh` | Drop mattpocock-skills |
| `README.md`, `docs/howto.md` | Docs |

---

### Task 1: Test harness, fake `npx`, fixtures

**Files:**
- Create: `tests/run.sh`, `tests/lib.sh`, `tests/fakes/npx`, `tests/fixtures/repo-acme_tools.txt`, `tests/fixtures/repo-acme_suite.txt`, `tests/fixtures/real-list-gsd-pi.txt`

**Interfaces:**
- Produces: `setup_sandbox` (exports `HOME`, `BOOTSTRAP_CONFIG_DIR`, `FAKE_NPX_LOG`, `FAKE_NPX_FIXTURES`, prepends `tests/fakes` to `PATH`, sets `NON_INTERACTIVE=1`), `load_libs` (sources `lib/common.sh lib/drivers.sh lib/ui.sh lib/skills.sh` with `REPO_ROOT` set), `assert_eq expected actual label`, `assert_contains haystack needle label`, `assert_not_contains`, `assert_ok label cmd...`, `assert_fail label cmd...`, `finish`.
- Fake repos: `acme/tools` → skills `alpha beta gamma`; `acme/suite` → `one two`.
- Fake CLI env knobs: `FAKE_NPX_FAIL=1` makes `add`/`remove` exit 1; `FAKE_NPX_LIST_FAIL=1` makes `-l` exit 1 with no output.

- [ ] **Step 1: Install shellcheck (dev dependency, one-time)**

Run: `brew install shellcheck`
Expected: `shellcheck --version` prints a version.

- [ ] **Step 2: Write `tests/lib.sh`**

```bash
#!/bin/bash
# Shared helpers for tests/test_*.sh. Each test file:
#   . "$(dirname "$0")/lib.sh"; setup_sandbox; load_libs; ...cases...; finish
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
PASSES=0
FAILS=0

assert_eq() { # expected actual label
  if [ "$1" = "$2" ]; then
    PASSES=$((PASSES + 1))
  else
    FAILS=$((FAILS + 1))
    printf 'FAIL %s\n  expected: [%s]\n  actual:   [%s]\n' "$3" "$1" "$2" >&2
  fi
}

assert_contains() { # haystack needle label
  case "$1" in
    *"$2"*) PASSES=$((PASSES + 1)) ;;
    *)
      FAILS=$((FAILS + 1))
      printf 'FAIL %s\n  missing: [%s]\n  in:      [%s]\n' "$3" "$2" "$1" >&2
      ;;
  esac
}

assert_not_contains() { # haystack needle label
  case "$1" in
    *"$2"*)
      FAILS=$((FAILS + 1))
      printf 'FAIL %s\n  unexpected: [%s]\n  in:         [%s]\n' "$3" "$2" "$1" >&2
      ;;
    *) PASSES=$((PASSES + 1)) ;;
  esac
}

assert_ok() { # label cmd args...
  local label="$1"
  shift
  if "$@"; then PASSES=$((PASSES + 1)); else
    FAILS=$((FAILS + 1))
    printf 'FAIL %s: expected exit 0 from: %s\n' "$label" "$*" >&2
  fi
}

assert_fail() { # label cmd args...
  local label="$1"
  shift
  if "$@"; then
    FAILS=$((FAILS + 1))
    printf 'FAIL %s: expected non-zero from: %s\n' "$label" "$*" >&2
  else PASSES=$((PASSES + 1)); fi
}

# Fresh HOME with empty store + agent dirs, isolated config dir, fake npx first
# on PATH, non-interactive by default. Call before load_libs (CONFIG_DIR is
# resolved when lib/common.sh is sourced).
setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills"
  export BOOTSTRAP_CONFIG_DIR="$SANDBOX/config"
  export FAKE_NPX_LOG="$SANDBOX/npx.log"
  : >"$FAKE_NPX_LOG"
  export FAKE_NPX_FIXTURES="$TESTS_DIR/fixtures"
  export PATH="$TESTS_DIR/fakes:$PATH"
  export NON_INTERACTIVE=1
  export DRY_RUN=0
}

load_libs() {
  # shellcheck source=/dev/null
  . "$REPO_ROOT/lib/common.sh"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/lib/drivers.sh"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/lib/ui.sh"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/lib/skills.sh"
}

npx_log() { cat "$FAKE_NPX_LOG"; }

finish() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASSES" "$FAILS"
  [ "$FAILS" = 0 ]
}
```

- [ ] **Step 3: Write `tests/run.sh`**

```bash
#!/bin/bash
# Run every tests/test_*.sh under the stock macOS bash (3.2) and shellcheck
# the sources. Exit 1 if anything fails.
set -u
cd "$(dirname "$0")/.." || exit 1
rc=0
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck lib/*.sh apps/*.sh run.sh update.sh install.sh tests/lib.sh tests/run.sh tests/fakes/npx tests/test_*.sh || rc=1
else
  echo "warning: shellcheck not installed (brew install shellcheck) — skipping lint" >&2
fi
for t in tests/test_*.sh; do
  [ -e "$t" ] || continue
  /bin/bash "$t" || rc=1
done
exit "$rc"
```

- [ ] **Step 4: Write the fake CLI `tests/fakes/npx`**

```bash
#!/bin/bash
# Fake `npx -y skills <cmd> ...` for tests. Logs each call (one line, the
# args as given) to $FAKE_NPX_LOG and simulates the skills.sh CLI against the
# sandbox HOME:
#   add <repo> -l                  print a CLI-style listing from
#                                  $FAKE_NPX_FIXTURES/repo-<owner_repo>.txt
#   add <repo> -g -y [-a A] -s N.. create $HOME/.agents/skills/N/SKILL.md,
#                                  link into agent dirs, record lock entries
#   remove -g -y N..               delete store dirs, links, lock entries
# FAKE_NPX_FAIL=1 makes add/remove exit 1; FAKE_NPX_LIST_FAIL=1 makes -l exit 1.
set -u
printf '%s\n' "$*" >>"${FAKE_NPX_LOG:?}"
[ "${1:-}" = -y ] && shift
if [ "${1:-}" != skills ]; then echo "fake npx: unexpected invocation: $*" >&2; exit 2; fi
shift
cmd="${1:-}"
shift || true
store="$HOME/.agents/skills"
lock="$HOME/.agents/.skill-lock.json"

fixture_for() { printf '%s/repo-%s.txt\n' "$FAKE_NPX_FIXTURES" "$(printf '%s' "$1" | tr '/' '_')"; }

lock_edit() { # add|del repo names...
  python3 - "$lock" "$@" <<'EOF'
import json, os, sys
lock, op, repo = sys.argv[1], sys.argv[2], sys.argv[3]
names = sys.argv[4:]
d = {"version": 2, "skills": {}}
if os.path.exists(lock):
    d = json.load(open(lock))
for n in names:
    if op == "add":
        d["skills"][n] = {"source": repo, "sourceType": "github",
                          "skillPath": "skills/%s/SKILL.md" % n}
    else:
        d["skills"].pop(n, None)
json.dump(d, open(lock, "w"), indent=1)
EOF
}

agent_dir() { case "$1" in codex) printf '%s/.codex/skills\n' "$HOME" ;; *) printf '%s/.claude/skills\n' "$HOME" ;; esac; }

case "$cmd" in
  add)
    repo="$1"; shift
    list=0; agents="claude-code codex"; names=""; mode=""
    for a in "$@"; do
      case "$a" in
        -l) list=1 ;;
        -g | -y) ;;
        -a) mode=a ;;
        -s) mode=s ;;
        *)
          case "$mode" in
            a) agents="$(printf '%s' "$a" | tr ',' ' ')" ;;
            s) names="$names $a" ;;
          esac
          ;;
      esac
    done
    fx="$(fixture_for "$repo")"
    if [ "$list" = 1 ]; then
      [ "${FAKE_NPX_LIST_FAIL:-0}" = 1 ] && exit 1
      [ -f "$fx" ] || { printf '\342\227\207  No skills found\n'; exit 0; }
      n="$(grep -c . "$fx")"
      printf '\033[1G\033[J\342\227\207  Found %s skills\n\342\224\202\n\342\227\207  Available Skills\n\342\224\202\n' "$n"
      while IFS="$(printf '\t')" read -r name desc; do
        [ -n "$name" ] || continue
        printf '\342\224\202    %s\n\342\224\202\n\342\224\202      %s\n\342\224\202\n' "$name" "$desc"
      done <"$fx"
      printf '\342\224\224  Use --skill <name> to install specific skills\n'
      exit 0
    fi
    [ "${FAKE_NPX_FAIL:-0}" = 1 ] && exit 1
    if [ "$(printf '%s' "$names" | tr -d ' ')" = '*' ]; then
      names="$(cut -f1 "$fx" | tr '\n' ' ')"
    fi
    for name in $names; do
      mkdir -p "$store/$name"
      printf -- '---\nname: %s\n---\n' "$name" >"$store/$name/SKILL.md"
      for ag in $agents; do
        d="$(agent_dir "$ag")"; mkdir -p "$d"; ln -sfn "$store/$name" "$d/$name"
      done
    done
    # shellcheck disable=SC2086
    lock_edit add "$repo" $names
    ;;
  remove)
    [ "${FAKE_NPX_FAIL:-0}" = 1 ] && exit 1
    names=""
    for a in "$@"; do case "$a" in -g | -y) ;; *) names="$names $a" ;; esac; done
    for name in $names; do
      rm -rf "$store/$name" "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name"
    done
    # shellcheck disable=SC2086
    lock_edit del - $names
    ;;
  *) echo "fake npx: unsupported command: $cmd" >&2; exit 2 ;;
esac
```

Run: `chmod +x tests/fakes/npx tests/run.sh`

- [ ] **Step 5: Write fixtures**

`tests/fixtures/repo-acme_tools.txt` (tab-separated):
```
alpha	First skill, does alpha things
beta	Second skill, does beta things
gamma	Third skill, does gamma things
```

`tests/fixtures/repo-acme_suite.txt`:
```
one	Suite skill one
two	Suite skill two
```

Real capture (network, one-time):
```bash
npx -y skills add open-gsd/gsd-pi -l >tests/fixtures/real-list-gsd-pi.txt 2>&1
grep -c gsd-orchestrator tests/fixtures/real-list-gsd-pi.txt   # expect >= 1
```

- [ ] **Step 6: Smoke-test the fake**

```bash
/bin/bash -c '
. tests/lib.sh; setup_sandbox
npx -y skills add acme/tools -l | grep -c "alpha"          # 1
npx -y skills add acme/tools -g -y -s alpha beta
ls "$HOME/.agents/skills"                                  # alpha beta
readlink "$HOME/.codex/skills/alpha"                       # .../alpha
npx -y skills add acme/suite -g -y -a codex -s "*"
ls "$HOME/.claude/skills"                                  # alpha beta (no one/two)
npx -y skills remove -g -y alpha
ls "$HOME/.agents/skills"                                  # beta one two
python3 -c "import json;print(sorted(json.load(open(\"$HOME/.agents/.skill-lock.json\"))[\"skills\"]))"
cat "$FAKE_NPX_LOG"'
```
Expected: as annotated; lock lists `['beta', 'one', 'two']`.

- [ ] **Step 7: Run harness (no tests yet) and commit**

Run: `tests/run.sh`
Expected: shellcheck passes (fix any findings in the new files only), no test files yet, exit 0.

```bash
git add tests
git commit -m "test: add bash test harness with a fake skills CLI"
```

---

### Task 2: `lib/skills.sh` — saved selection (`skills.conf`)

**Files:**
- Create: `lib/skills.sh`
- Test: `tests/test_skills_conf.sh`

**Interfaces:**
- Produces: `skills_conf_file`, `skills_var_name repo`, `skills_conf_get repo` (prints value, exit 1 when no line), `skills_conf_put repo value`, `skills_conf_delete repo`. Under `DRY_RUN=1`, put/delete only log.

- [ ] **Step 1: Write the failing test**

`tests/test_skills_conf.sh`:
```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/test_skills_conf.sh`
Expected: fails at `load_libs` — `lib/skills.sh: No such file or directory`.

- [ ] **Step 3: Write `lib/skills.sh` (conf part)**

```bash
#!/bin/bash
# Shared engine for the agent-skill units (apps/agent-skills.sh,
# apps/agent-skill-suites.sh). Sourced after lib/common.sh and lib/drivers.sh;
# lib/ui.sh is optional (present only in interactive run.sh).
#
# Everything about the skills.sh CLI (`npx skills`) lives here: listing a
# repo's skills, installing/removing by name, reading the CLI's lock file,
# the per-machine saved selection in $CONFIG_DIR/skills.conf, and purging
# known untracked leftovers. Units hold only a roster and delegate.
#
# Roster format (one record per line): owner/repo|agents|default-skills
#   agents         "*" (every detected agent) or names such as "codex"
#   default-skills space-separated names, or "*" = track the whole repo
#
# Invariants: never a bare `skills update`; `skills remove` only ever gets
# explicit names taken from the lock file for the unit's own repos.

SKILLS_STORE="${SKILLS_STORE:-$HOME/.agents/skills}"
SKILLS_LOCK="${SKILLS_LOCK:-$HOME/.agents/.skill-lock.json}"

# ---- saved selection: $CONFIG_DIR/skills.conf --------------------------------
# Shell-sourced like apps.conf; one SKILLS_<repo> line per repo. "*" means
# track every skill the repo publishes; an empty value is a saved "nothing".

skills_conf_file() { printf '%s/skills.conf\n' "$CONFIG_DIR"; }

# owner/repo -> SKILLS_owner__repo ("/" -> "__", anything else odd -> "_")
skills_var_name() {
  printf 'SKILLS_%s\n' "$(printf '%s' "$1" | sed -e 's#/#__#g' -e 's/[^A-Za-z0-9_]/_/g')"
}

# Prints the saved value for a repo; exit 1 when the repo has no line.
skills_conf_get() {
  local cf var
  cf="$(skills_conf_file)"
  var="$(skills_var_name "$1")"
  if [ ! -f "$cf" ]; then return 1; fi
  if ! grep -q "^${var}=" "$cf"; then return 1; fi
  # shellcheck source=/dev/null
  (. "$cf" && eval "printf '%s\n' \"\${$var}\"")
}

skills_conf_write() { # var value|"" delete
  local cf tmp var="$1" value="$2" op="$3"
  cf="$(skills_conf_file)"
  mkdir -p "$CONFIG_DIR"
  tmp="$cf.tmp.$$"
  {
    printf '# Managed by run.sh — per-machine agent skill selection (one line per\n'
    printf '# repo; "*" = track every skill the repo publishes).\n'
    if [ -f "$cf" ]; then grep -v -e '^#' -e '^$' -e "^${var}=" "$cf" || true; fi
    if [ "$op" = put ]; then printf '%s="%s"\n' "$var" "$value"; fi
  } >"$tmp"
  mv "$tmp" "$cf"
}

skills_conf_put() { # repo value
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] save skill selection for $1: [${2:-<none>}] in $(skills_conf_file)"
    return 0
  fi
  skills_conf_write "$(skills_var_name "$1")" "$2" put
}

skills_conf_delete() { # repo
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] drop skill selection for $1 from $(skills_conf_file)"
    return 0
  fi
  if [ -f "$(skills_conf_file)" ]; then skills_conf_write "$(skills_var_name "$1")" "" delete; fi
}
```

- [ ] **Step 4: Run the test**

Run: `/bin/bash tests/test_skills_conf.sh`
Expected: `test_skills_conf.sh: 14 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

Run: `shellcheck lib/skills.sh tests/test_skills_conf.sh`
```bash
git add lib/skills.sh tests/test_skills_conf.sh
git commit -m "feat(skills): saved per-repo skill selection in skills.conf"
```

---

### Task 3: `lib/skills.sh` — upstream listing, lock file, agent dirs, npx

**Files:**
- Modify: `lib/skills.sh` (append)
- Test: `tests/test_skills_query.sh`

**Interfaces:**
- Produces: `skills_require_npx`, `skills_list_upstream repo` (prints `name<TAB>desc` lines; exit 1 on failure/no skills; cached per process), `skills_upstream_names repo` (space-separated names, same exit code), `skills_lock_names repo` (one name per line), `skills_lock_has name`, `skills_agent_dir agent`, `skills_agents_ready agents`, `skills_roster_count roster`, `skills_roster_record roster n`, `skills_roster_field record 1|2|3`.

- [ ] **Step 1: Write the failing test**

`tests/test_skills_query.sh`:
```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs

# listing + parser (fake CLI)
out="$(skills_list_upstream acme/tools)"
assert_eq "$(printf 'alpha\tFirst skill, does alpha things\nbeta\tSecond skill, does beta things\ngamma\tThird skill, does gamma things')" "$out" "parses names and first description line"
assert_eq "alpha beta gamma" "$(skills_upstream_names acme/tools)" "names joined by spaces"
assert_eq "1" "$(grep -c 'add acme/tools -l' "$FAKE_NPX_LOG")" "listing hit the CLI once"
skills_upstream_names acme/tools >/dev/null
assert_eq "1" "$(grep -c 'add acme/tools -l' "$FAKE_NPX_LOG")" "second call served from cache"
assert_fail "unknown repo (no skills found) fails" skills_list_upstream acme/nothing
FAKE_NPX_LIST_FAIL=1 assert_fail "CLI failure propagates" skills_list_upstream acme/other

# parser against a real capture (ANSI, box drawing, wrapped description)
real="$(skills_parse_listing <"$TESTS_DIR/fixtures/real-list-gsd-pi.txt")"
assert_eq "gsd-orchestrator" "$(printf '%s\n' "$real" | cut -f1)" "real capture: name"
assert_contains "$(printf '%s\n' "$real" | cut -f2)" "Build software products autonomously" "real capture: description"

# lock file
assert_eq "" "$(skills_lock_names acme/tools)" "no lock file -> empty"
npx -y skills add acme/tools -g -y -s alpha beta >/dev/null
npx -y skills add acme/suite -g -y -s one >/dev/null
assert_eq "$(printf 'alpha\nbeta')" "$(skills_lock_names acme/tools)" "lock names filtered by source"
assert_ok "lock_has known" skills_lock_has one
assert_fail "lock_has unknown" skills_lock_has gamma

# agents
assert_eq "$HOME/.codex/skills" "$(skills_agent_dir codex)" "codex dir"
assert_ok "star agents always ready" skills_agents_ready "*"
assert_ok "codex ready when dir exists" skills_agents_ready codex
rm -rf "$HOME/.codex/skills"
assert_fail "codex not ready when dir missing" skills_agents_ready codex

# roster helpers
R="a/one|*|x y
b/two|codex|*"
assert_eq "2" "$(skills_roster_count "$R")" "count"
assert_eq "b/two|codex|*" "$(skills_roster_record "$R" 2)" "record 2"
assert_eq "x y" "$(skills_roster_field "$(skills_roster_record "$R" 1)" 3)" "field 3"
assert_eq "codex" "$(skills_roster_field "b/two|codex|*" 2)" "field 2"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/test_skills_query.sh`
Expected: `skills_list_upstream: command not found` and many FAILs.

- [ ] **Step 3: Append to `lib/skills.sh`**

```bash

# ---- npx ---------------------------------------------------------------------

skills_require_npx() {
  if ! command -v npx >/dev/null 2>&1; then
    log "npx not found — installing Node.js first"
    formula_install node
  fi
  if ! command -v npx >/dev/null 2>&1 && [ "$DRY_RUN" != 1 ]; then
    err "npx still not available — install Node.js and retry"
    return 1
  fi
}

# ---- upstream listing --------------------------------------------------------

# stdin: raw `skills add <repo> -l` output -> stdout: "name<TAB>description"
# per skill (description = first line under the name, may be empty). The CLI
# draws a box: names are "│" + 4 spaces + name, descriptions "│" + 6 spaces.
skills_parse_listing() {
  python3 -c '
import re, sys
ansi = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
name = None
for raw in sys.stdin:
    line = ansi.sub("", raw).rstrip("\n")
    if not line.startswith("│"):
        continue
    body = line[1:]
    m = re.match(r"^    ([A-Za-z0-9][A-Za-z0-9._-]*)$", body)
    if m:
        if name:
            print(name + "\t")
        name = m.group(1)
        continue
    m = re.match(r"^      (\S.*)$", body)
    if m and name:
        print(name + "\t" + m.group(1).strip())
        name = None
if name:
    print(name + "\t")
'
}

# Prints "name<TAB>description" lines for a repo; exit 1 when the CLI fails
# or finds nothing. Cached per process (one network round trip per repo).
skills_list_upstream() {
  local repo="$1" cache raw
  if [ -z "${SKILLS_CACHE_DIR:-}" ]; then SKILLS_CACHE_DIR="$(mktemp -d)"; fi
  cache="$SKILLS_CACHE_DIR/$(printf '%s' "$repo" | tr '/' '_')"
  if [ -f "$cache" ]; then cat "$cache"; return 0; fi
  if ! raw="$(npx -y skills add "$repo" -l 2>&1)"; then return 1; fi
  printf '%s\n' "$raw" | skills_parse_listing >"$cache.tmp"
  if ! grep -q . "$cache.tmp"; then rm -f "$cache.tmp"; return 1; fi
  mv "$cache.tmp" "$cache"
  cat "$cache"
}

skills_upstream_names() { # repo -> "a b c"
  local items
  items="$(skills_list_upstream "$1")" || return 1
  printf '%s\n' "$items" | cut -f1 | tr '\n' ' ' | sed 's/ $//'
  printf '\n'
}

# ---- lock file ---------------------------------------------------------------
# ~/.agents/.skill-lock.json: {"skills": {name: {"source": "owner/repo", ...}}}

skills_lock_names() { # repo -> one installed name per line
  if [ ! -f "$SKILLS_LOCK" ]; then return 0; fi
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found — cannot read $SKILLS_LOCK; treating it as empty"
    return 0
  fi
  python3 - "$SKILLS_LOCK" "$1" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:  # unreadable lock: warn, act as empty
    sys.stderr.write("warning: cannot read %s: %s\n" % (sys.argv[1], e))
    sys.exit(0)
for n, v in sorted(d.get("skills", {}).items()):
    if v.get("source") == sys.argv[2]:
        print(n)
EOF
}

skills_lock_has() { # name -> 0 if any source tracks it
  if [ ! -f "$SKILLS_LOCK" ] || ! command -v python3 >/dev/null 2>&1; then return 1; fi
  python3 - "$SKILLS_LOCK" "$1" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in d.get("skills", {}) else 1)
EOF
}

# ---- agents ------------------------------------------------------------------

skills_agent_dir() {
  case "$1" in
    codex) printf '%s/.codex/skills\n' "$HOME" ;;
    claude | claude-code) printf '%s/.claude/skills\n' "$HOME" ;;
    *) printf '%s/.%s/skills\n' "$HOME" "$1" ;;
  esac
}

# 0 when agents is "*" or every named agent's skills dir exists.
skills_agents_ready() {
  local a
  if [ "$1" = "*" ]; then return 0; fi
  for a in $1; do
    if [ ! -d "$(skills_agent_dir "$a")" ]; then return 1; fi
  done
}

# ---- roster helpers ----------------------------------------------------------
# Line-numbered access so callers can prompt (read stdin) inside the loop.

skills_roster_count() { printf '%s\n' "$1" | grep -c '|'; }
skills_roster_record() { printf '%s\n' "$1" | grep '|' | sed -n "${2}p"; }
skills_roster_field() { printf '%s\n' "$1" | cut -d'|' -f"$2"; }
```

- [ ] **Step 4: Run the test**

Run: `/bin/bash tests/test_skills_query.sh`
Expected: `test_skills_query.sh: 22 passed, 0 failed`. If the real-capture assertions fail, inspect `tests/fixtures/real-list-gsd-pi.txt` with `cat -v` and adjust only the two regexes in `skills_parse_listing`.

- [ ] **Step 5: Lint and commit**

Run: `tests/run.sh`
```bash
git add lib/skills.sh tests/test_skills_query.sh
git commit -m "feat(skills): list upstream skills, read the CLI lock file, roster helpers"
```

---

### Task 4: `select_from_list` in `lib/ui.sh`

**Files:**
- Modify: `lib/ui.sh` (add after `select_apps`, before `prompt_confirm`)
- Test: `tests/test_select_from_list.sh`

**Interfaces:**
- Produces: `select_from_list title items current new_names` → stdout: `*` when every item ends up checked, else space-separated chosen names in upstream order (possibly empty). `items` = newline-separated `name<TAB>desc`; `current` = names or `*`; `new_names` = names to tag `(new)`. All prompts/rows go to stderr; input from stdin; EOF = confirm.

- [ ] **Step 1: Write the failing test**

`tests/test_select_from_list.sh`:
```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
ITEMS="$(printf 'alpha\tFirst\nbeta\tSecond\ngamma\tThird')"

sel="$(printf '\n' | select_from_list "T" "$ITEMS" "alpha gamma" "" 2>/dev/null)"
assert_eq "alpha gamma" "$sel" "Enter confirms the pre-checked set"

sel="$(printf '2\n\n' | select_from_list "T" "$ITEMS" "alpha gamma" "" 2>/dev/null)"
assert_eq "*" "$sel" "checking the last unchecked item yields *"

sel="$(printf '1\n\n' | select_from_list "T" "$ITEMS" "*" "" 2>/dev/null)"
assert_eq "beta gamma" "$sel" "unchecking one from * yields explicit list"

sel="$(printf 'n\n\n' | select_from_list "T" "$ITEMS" "*" "" 2>/dev/null)"
assert_eq "" "$sel" "n clears everything"

sel="$(printf 'a\n\n' | select_from_list "T" "$ITEMS" "" "" 2>/dev/null)"
assert_eq "*" "$sel" "a selects everything"

sel="$(printf '3 1\n\n' | select_from_list "T" "$ITEMS" "" "" 2>/dev/null)"
assert_eq "alpha gamma" "$sel" "output keeps upstream order regardless of toggle order"

sel="$(printf '' | select_from_list "T" "$ITEMS" "beta" "" 2>/dev/null)"
assert_eq "beta" "$sel" "EOF confirms"

screen="$(printf '\n' | select_from_list "Title here" "$ITEMS" "alpha" "gamma" 2>&1 >/dev/null)"
assert_contains "$screen" "Title here" "title shown"
assert_contains "$screen" "1) [x] alpha" "checked row"
assert_contains "$screen" "2) [ ] beta" "unchecked row"
assert_contains "$screen" "(new)" "new tag shown"
assert_contains "$screen" "First" "description shown"
assert_contains "$screen" "1 of 3 selected" "count line"
screen="$(printf '\n' | select_from_list "T" "$ITEMS" "*" "" 2>&1 >/dev/null)"
assert_contains "$screen" 'saved as "*"' "star notice when all checked"

screen="$(printf '9 x\n\n' | select_from_list "T" "$ITEMS" "" "" 2>&1 >/dev/null)"
assert_contains "$screen" "out of range: 9" "range warning"
assert_contains "$screen" "not a number: x" "number warning"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/test_select_from_list.sh`
Expected: `select_from_list: command not found`.

- [ ] **Step 3: Implement in `lib/ui.sh`**

Insert after the closing `}` of `select_apps`:

```bash

# select_from_list title items current new_names -> prints the selection.
# items: newline-separated "name<TAB>description"; current: space-separated
# names or "*" (= all); new_names: names to tag "(new)". Rows and prompts go
# to stderr so the result can be captured from stdout. Same grammar as the
# app checklist. Prints "*" when every item is checked (track-all), otherwise
# the checked names in item order — possibly nothing. EOF on stdin confirms.
select_from_list() {
  local title="$1" items="$2" current="$3" new_names="$4"
  local names total width n name desc mark tag input tok picked count
  names="$(printf '%s\n' "$items" | cut -f1 | grep . || true)"
  total="$(printf '%s\n' "$names" | grep -c . || true)"
  if [ "$current" = "*" ]; then current="$(printf '%s\n' "$names" | tr '\n' ' ')"; fi
  width="$(tput cols 2>/dev/null || echo 120)"
  while :; do
    printf '\n%s\n' "$title" >&2
    n=0
    while IFS="$(printf '\t')" read -r name desc; do
      if [ -z "$name" ]; then continue; fi
      n=$((n + 1))
      mark=" "
      if in_list "$name" "$current"; then mark=x; fi
      tag=""
      if in_list "$name" "$new_names"; then tag=" (new)"; fi
      printf '  %3d) [%s] %-30s%s  %s\n' "$n" "$mark" "$name" "$tag" "$desc" | cut -c1-"$width" >&2
    done <<<"$items"
    count=0
    for name in $names; do
      if in_list "$name" "$current"; then count=$((count + 1)); fi
    done
    if [ "$count" -eq "$total" ] && [ "$total" -gt 0 ]; then
      printf '  all %d selected — saved as "*" (tracks skills added upstream later)\n' "$total" >&2
    else
      printf '  %d of %d selected\n' "$count" "$total" >&2
    fi
    printf 'Toggle numbers (space-separated), a=all, n=none, Enter=confirm: ' >&2
    if ! read -r input; then input=""; printf '\n' >&2; fi
    case "$input" in
      "") break ;;
      a) current="$(printf '%s\n' "$names" | tr '\n' ' ')" ;;
      n) current="" ;;
      *)
        for tok in $input; do
          case "$tok" in
            *[!0-9]*) warn "not a number: $tok" ;;
            *)
              if [ "$tok" -ge 1 ] && [ "$tok" -le "$total" ]; then
                name="$(printf '%s\n' "$names" | sed -n "$((10#$tok))p")"
                if in_list "$name" "$current"; then
                  current="$(remove_from_list "$name" "$current")"
                else
                  current="$current $name"
                fi
              else
                warn "out of range: $tok"
              fi
              ;;
          esac
        done
        ;;
    esac
  done
  picked=""
  count=0
  for name in $names; do
    if in_list "$name" "$current"; then picked="$picked $name"; count=$((count + 1)); fi
  done
  if [ "$count" -eq "$total" ] && [ "$total" -gt 0 ]; then
    printf '*\n'
  else
    printf '%s\n' "${picked# }"
  fi
}
```

- [ ] **Step 4: Run the test**

Run: `/bin/bash tests/test_select_from_list.sh`
Expected: `test_select_from_list.sh: 16 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

Run: `tests/run.sh`
```bash
git add lib/ui.sh tests/test_select_from_list.sh
git commit -m "feat(ui): generic select_from_list checklist"
```

---

### Task 5: `lib/skills.sh` — reconcile and purge

**Files:**
- Modify: `lib/skills.sh` (append)
- Test: `tests/test_skills_reconcile.sh`

**Interfaces:**
- Consumes: `skills_lock_names`, `skills_lock_has`, `skills_upstream_names`, `skills_agents_ready`, `run_cmd`.
- Produces: `skills_reconcile repo agents selected` (selected = names, `*`, or empty), `skills_purge_untracked names`.

- [ ] **Step 1: Write the failing test**

`tests/test_skills_reconcile.sh`:
```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs

# explicit list installs exactly those names for all agents
skills_reconcile acme/tools "*" "alpha beta"
assert_eq "alpha beta" "$(ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//')" "explicit add"
assert_contains "$(npx_log)" "skills add acme/tools -g -y -s alpha beta" "add command shape"
assert_not_contains "$(npx_log)" " -a " "no -a for star agents"

# shrinking the list removes the stale name (lock - selected)
skills_reconcile acme/tools "*" "alpha"
assert_eq "alpha" "$(ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//')" "stale removed"
assert_contains "$(npx_log)" "skills remove -g -y beta" "remove only the stale name"

# star: installs with -s '*' and removes lock names no longer upstream
mkdir -p "$HOME/.agents/skills/ghost"
python3 - "$HOME/.agents/.skill-lock.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["skills"]["ghost"] = {"source": "acme/tools"}
json.dump(d, open(sys.argv[1], "w"))
EOF
skills_reconcile acme/tools "*" "*"
assert_contains "$(npx_log)" "skills add acme/tools -g -y -s *" "star passed literally"
assert_eq "alpha beta gamma" "$(ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//')" "star installs all, ghost removed"
assert_contains "$(npx_log)" "skills remove -g -y ghost" "ghost removed by name"

# codex-only agents flag, comma-joined
skills_reconcile acme/suite "codex" "one"
assert_contains "$(npx_log)" "skills add acme/suite -g -y -a codex -s one" "agents flag"
assert_ok "linked into codex" test -L "$HOME/.codex/skills/one"
assert_fail "not linked into claude" test -e "$HOME/.claude/skills/one"

# missing agent dir -> skipped, exit 0, nothing run
: >"$FAKE_NPX_LOG"
rm -rf "$HOME/.codex/skills"
assert_ok "skip is not a failure" skills_reconcile acme/suite "codex" "two"
assert_eq "" "$(npx_log)" "nothing invoked when agent dir missing"
mkdir -p "$HOME/.codex/skills"

# empty selection: no add, stale removal still happens
skills_reconcile acme/suite "codex" ""
assert_not_contains "$(npx_log)" "add acme/suite" "no add for empty selection"
assert_contains "$(npx_log)" "skills remove -g -y one" "empty selection removes previous"

# failures propagate
FAKE_NPX_FAIL=1 assert_fail "add failure -> non-zero" skills_reconcile acme/tools "*" "alpha"

# dry run: prints, changes nothing
: >"$FAKE_NPX_LOG"
out="$(DRY_RUN=1 skills_reconcile acme/suite "*" "two")"
assert_contains "$out" "[dry-run] npx -y skills add acme/suite -g -y -s two" "dry-run echoes add"
assert_eq "" "$(npx_log)" "dry-run does not call the CLI"

# purge: untracked copies go, tracked ones stay
mkdir -p "$HOME/.agents/skills/leftover" "$HOME/.claude/skills/leftover-link-target"
ln -s "$HOME/.claude/skills/leftover-link-target" "$HOME/.claude/skills/leftover"
skills_purge_untracked "leftover alpha nonexistent"
assert_fail "untracked store dir removed" test -e "$HOME/.agents/skills/leftover"
assert_fail "untracked agent link removed" test -L "$HOME/.claude/skills/leftover"
assert_ok "tracked skill kept" test -d "$HOME/.agents/skills/alpha"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/test_skills_reconcile.sh`
Expected: `skills_reconcile: command not found`.

- [ ] **Step 3: Append to `lib/skills.sh`**

```bash

# ---- reconcile ---------------------------------------------------------------

# skills_reconcile repo agents selected
#   selected: space-separated names, "*" (track the whole repo), or "".
# add refreshes installed skills in place (verified 2026-09-08), so this is
# both install and update. Stale = lock names for this repo that are not
# selected (or, for "*", not published upstream any more) — removed by name.
skills_reconcile() {
  local repo="$1" agents="$2" selected="$3" rc=0 name stale="" lock upstream
  local aflag=() # bash 3.2: guard expansion below
  if ! skills_agents_ready "$agents"; then
    log "$repo: skipped — agent dir missing for '$agents' (installed on a later update once the agent exists)"
    return 0
  fi
  if [ "$agents" != "*" ]; then aflag=(-a "$(printf '%s' "$agents" | tr ' ' ',')"); fi
  if [ "$selected" = "*" ]; then
    if ! run_cmd npx -y skills add "$repo" -g -y ${aflag[@]+"${aflag[@]}"} -s '*'; then
      err "$repo: skills add failed"
      rc=1
    fi
  elif [ -n "$selected" ]; then
    # shellcheck disable=SC2086
    if ! run_cmd npx -y skills add "$repo" -g -y ${aflag[@]+"${aflag[@]}"} -s $selected; then
      err "$repo: skills add failed"
      rc=1
    fi
  fi
  lock="$(skills_lock_names "$repo" | tr '\n' ' ')"
  if [ "$selected" = "*" ]; then
    if upstream="$(skills_upstream_names "$repo")"; then
      for name in $lock; do
        if ! in_list "$name" "$upstream"; then stale="$stale $name"; fi
      done
    else
      log "$repo: cannot list upstream — skipping removal of skills upstream dropped"
    fi
  else
    for name in $lock; do
      if ! in_list "$name" "$selected"; then stale="$stale $name"; fi
    done
  fi
  if [ -n "$stale" ]; then
    # shellcheck disable=SC2086
    run_cmd npx -y skills remove -g -y $stale || rc=1
  fi
  return "$rc"
}

# ---- purge -------------------------------------------------------------------

# Delete known untracked leftovers (hand-copied skills with no lock entry)
# from the store and the agent link dirs. A name the lock tracks is never
# touched, whatever its source.
skills_purge_untracked() {
  local name d
  for name in $1; do
    if skills_lock_has "$name"; then continue; fi
    for d in "$SKILLS_STORE/$name" "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name"; do
      if [ -e "$d" ] || [ -L "$d" ]; then
        log "removing untracked local skill copy: $d"
        run_cmd rm -rf "$d"
      fi
    done
  done
}
```

- [ ] **Step 4: Run the test**

Run: `/bin/bash tests/test_skills_reconcile.sh`
Expected: `test_skills_reconcile.sh: 22 passed, 0 failed`.

- [ ] **Step 5: Lint and commit**

Run: `tests/run.sh`
```bash
git add lib/skills.sh tests/test_skills_reconcile.sh
git commit -m "feat(skills): lock-driven reconcile and purge of untracked leftovers"
```

---

### Task 6: `lib/skills.sh` — unit operations; source the engine from the entry points

**Files:**
- Modify: `lib/skills.sh` (append), `run.sh:72`, `update.sh:19`
- Test: `tests/test_skills_unit.sh`

**Interfaces:**
- Consumes: everything above plus `select_from_list`, `prompt_confirm` (both optional, from `lib/ui.sh`).
- Produces: `skills_unit_install unit roster purge`, `skills_unit_update unit roster purge`, `skills_unit_uninstall unit roster keep|zap`, `skills_unit_installed unit roster`, `skills_interactive`, `skills_select_repo unit repo saved has_saved defaults`.
- Behaviour: install and update share `skills_unit_sync`. A unit synced once in this process is not synced again (run.sh calls install then update back to back). Reselect prompt only when at least one roster repo has a saved line, only when interactive.

- [ ] **Step 1: Write the failing test**

`tests/test_skills_unit.sh`:
```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
ROSTER="acme/tools|*|alpha gamma
acme/suite|codex|*"
UNIT="Test unit"

# --- non-interactive first install: defaults, saved, installed
assert_fail "not installed before" skills_unit_installed "$UNIT" "$ROSTER"
assert_ok "install" skills_unit_install "$UNIT" "$ROSTER" ""
assert_eq "alpha gamma" "$(skills_conf_get acme/tools)" "defaults saved (names)"
assert_eq "*" "$(skills_conf_get acme/suite)" "defaults saved (star stays star)"
assert_eq "alpha gamma one two" "$(ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//')" "store after install"
assert_ok "installed after" skills_unit_installed "$UNIT" "$ROSTER"

# --- update right after install in the same process is a no-op
: >"$FAKE_NPX_LOG"
assert_ok "update (same process)" skills_unit_update "$UNIT" "$ROSTER" ""
assert_eq "" "$(npx_log)" "no CLI calls: unit already synced this process"

# --- fresh process: update honours the saved selection (no prompt, no reselect)
skills_conf_put acme/tools "beta"
unset SKILLS_SYNCED_UNITS
: >"$FAKE_NPX_LOG"
assert_ok "update (new process)" skills_unit_update "$UNIT" "$ROSTER" ""
assert_contains "$(npx_log)" "add acme/tools -g -y -s beta" "update installs saved list"
assert_contains "$(npx_log)" "remove -g -y alpha gamma" "update removes deselected"
assert_eq "beta" "$(skills_conf_get acme/tools)" "saved selection untouched by non-interactive update"

# --- purge list runs on sync
mkdir -p "$HOME/.agents/skills/oldcopy"
unset SKILLS_SYNCED_UNITS
skills_unit_update "$UNIT" "$ROSTER" "oldcopy" >/dev/null
assert_fail "purged" test -e "$HOME/.agents/skills/oldcopy"

# --- installed: missing saved name -> not installed; missing agent dir -> tolerated
rm -rf "$HOME/.agents/skills/beta"
assert_fail "missing selected skill -> not installed" skills_unit_installed "$UNIT" "$ROSTER"
mkdir -p "$HOME/.agents/skills/beta"
rm -rf "$HOME/.codex/skills"
assert_ok "missing codex dir does not fail installed" skills_unit_installed "$UNIT" "$ROSTER"
mkdir -p "$HOME/.codex/skills"

# --- interactive first install drives the checklist; reselect prompt on update
export NON_INTERACTIVE=0
rm -f "$(skills_conf_file)"
unset SKILLS_SYNCED_UNITS
# tools: toggle 2 (beta) on top of defaults alpha gamma -> all -> "*"; suite: Enter -> "*"
printf '2\n\n\n' | skills_unit_install "$UNIT" "$ROSTER" "" >/dev/null 2>&1
assert_eq "*" "$(skills_conf_get acme/tools)" "interactive install saved checklist result"
assert_eq "*" "$(skills_conf_get acme/suite)" "second repo got its own checklist"
unset SKILLS_SYNCED_UNITS
: >"$FAKE_NPX_LOG"
screen="$(printf '\n' | skills_unit_update "$UNIT" "$ROSTER" "" 2>&1 >/dev/null)"
assert_contains "$screen" "Reselect skills for Test unit? [y/N]" "reselect prompt shown"
assert_eq "*" "$(skills_conf_get acme/tools)" "Enter keeps selection"
unset SKILLS_SYNCED_UNITS
# y -> tools checklist: uncheck 1 (alpha) -> "beta gamma"; suite: Enter
printf 'y\n1\n\n\n' | skills_unit_update "$UNIT" "$ROSTER" "" >/dev/null 2>&1
assert_eq "beta gamma" "$(skills_conf_get acme/tools)" "reselect saved"
assert_contains "$(npx_log)" "remove -g -y alpha" "reselect removed alpha"
export NON_INTERACTIVE=1

# --- uninstall keep / zap
unset SKILLS_SYNCED_UNITS
: >"$FAKE_NPX_LOG"
npx -y skills add other/repo -g -y -s zeta >/dev/null   # foreign skill must survive
assert_ok "uninstall keep" skills_unit_uninstall "$UNIT" "$ROSTER" keep
assert_eq "zeta" "$(ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//')" "only the unit's skills removed"
assert_ok "conf kept" skills_conf_get acme/tools
assert_fail "not installed after uninstall" skills_unit_installed "$UNIT" "$ROSTER"
assert_ok "uninstall zap" skills_unit_uninstall "$UNIT" "$ROSTER" zap
assert_fail "zap drops conf line" skills_conf_get acme/tools
assert_fail "zap drops conf line (2)" skills_conf_get acme/suite

# --- offline first install: explicit defaults still install, star repo installs with -s *
unset SKILLS_SYNCED_UNITS
: >"$FAKE_NPX_LOG"
export NON_INTERACTIVE=0
FAKE_NPX_LIST_FAIL=1 skills_unit_install "$UNIT" "$ROSTER" "" >/dev/null 2>&1
assert_eq "alpha gamma" "$(skills_conf_get acme/tools)" "offline falls back to defaults"
assert_contains "$(npx_log)" "add acme/suite -g -y -a codex -s *" "offline star still installs"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/test_skills_unit.sh`
Expected: `skills_unit_installed: command not found`.

- [ ] **Step 3: Append to `lib/skills.sh`**

```bash

# ---- selection ---------------------------------------------------------------

# Interactive only under run.sh without --non-interactive, and only when
# lib/ui.sh is loaded (update.sh never sources it).
skills_interactive() {
  [ "${NON_INTERACTIVE:-1}" = 0 ] && command -v select_from_list >/dev/null 2>&1
}

# skills_select_repo unit repo saved has_saved defaults -> prints selection.
# Lists the repo live; pre-checks the saved selection (or the roster defaults
# on first install); tags skills new since the saved list. Falls back to the
# saved selection or the defaults when upstream cannot be listed. stdout is
# captured — nothing here may call log.
skills_select_repo() {
  local unit="$1" repo="$2" saved="$3" has_saved="$4" defaults="$5"
  local items names pre new="" name total fallback
  if [ "$has_saved" = 1 ]; then fallback="$saved"; else fallback="$defaults"; fi
  if ! items="$(skills_list_upstream "$repo")"; then
    warn "$repo: cannot list upstream skills — keeping [${fallback:-<none>}]"
    printf '%s\n' "$fallback"
    return 0
  fi
  names="$(printf '%s\n' "$items" | cut -f1 | tr '\n' ' ')"
  total="$(printf '%s\n' "$items" | grep -c .)"
  pre="$fallback"
  if [ "$has_saved" = 1 ] && [ "$saved" != "*" ]; then
    for name in $names; do
      if ! in_list "$name" "$saved"; then new="$new $name"; fi
    done
    for name in $saved; do
      if ! in_list "$name" "$names"; then warn "$repo: '$name' is no longer published upstream — dropped from the selection"; fi
    done
  fi
  select_from_list "$unit — $repo ($total upstream)" "$items" "$pre" "$new"
}

# ---- unit operations ---------------------------------------------------------
# run.sh calls <id>_install then <id>_update for a newly selected unit; the
# second pass would re-prompt and re-clone, so a unit synced in this process
# is remembered in SKILLS_SYNCED_UNITS and skipped.

skills_unit_sync() { # unit roster purge
  local unit="$1" roster="$2" purge="$3"
  local n i rec repo agents defaults saved has_saved sel any_saved=0 reselect=0 rc=0
  if in_list "$unit" "${SKILLS_SYNCED_UNITS:-}"; then return 0; fi
  skills_require_npx || return 1
  n="$(skills_roster_count "$roster")"
  i=1
  while [ "$i" -le "$n" ]; do
    repo="$(skills_roster_field "$(skills_roster_record "$roster" "$i")" 1)"
    if skills_conf_get "$repo" >/dev/null; then any_saved=1; fi
    i=$((i + 1))
  done
  if [ "$any_saved" = 1 ] && skills_interactive && prompt_confirm "Reselect skills for $unit?"; then
    reselect=1
  fi
  if [ -n "$purge" ]; then skills_purge_untracked "$purge"; fi
  i=1
  while [ "$i" -le "$n" ]; do
    rec="$(skills_roster_record "$roster" "$i")"
    i=$((i + 1))
    repo="$(skills_roster_field "$rec" 1)"
    agents="$(skills_roster_field "$rec" 2)"
    defaults="$(skills_roster_field "$rec" 3)"
    has_saved=0
    saved=""
    if saved="$(skills_conf_get "$repo")"; then has_saved=1; fi
    sel="$saved"
    if [ "$has_saved" = 0 ]; then
      if skills_interactive; then
        sel="$(skills_select_repo "$unit" "$repo" "" 0 "$defaults")"
      else
        sel="$defaults"
      fi
      skills_conf_put "$repo" "$sel"
    elif [ "$reselect" = 1 ]; then
      sel="$(skills_select_repo "$unit" "$repo" "$saved" 1 "$defaults")"
      if [ "$sel" != "$saved" ]; then skills_conf_put "$repo" "$sel"; fi
    fi
    skills_reconcile "$repo" "$agents" "$sel" || rc=1
  done
  SKILLS_SYNCED_UNITS="${SKILLS_SYNCED_UNITS:-} $unit"
  return "$rc"
}

skills_unit_install() { skills_unit_sync "$@"; }
skills_unit_update() { skills_unit_sync "$@"; }

# Removes every skill the lock attributes to the unit's repos — nothing else.
# keep leaves skills.conf alone; zap drops the unit's lines too.
skills_unit_uninstall() { # unit roster keep|zap
  local unit="$1" roster="$2" mode="${3:-keep}" n i repo names=""
  skills_require_npx || return 1
  n="$(skills_roster_count "$roster")"
  i=1
  while [ "$i" -le "$n" ]; do
    repo="$(skills_roster_field "$(skills_roster_record "$roster" "$i")" 1)"
    names="$names $(skills_lock_names "$repo" | tr '\n' ' ')"
    i=$((i + 1))
  done
  # shellcheck disable=SC2086
  set -- $names
  if [ "$#" -gt 0 ]; then
    run_cmd npx -y skills remove -g -y "$@" || return 1
  else
    log "$unit: no managed skills installed"
  fi
  if [ "$mode" = zap ]; then
    i=1
    while [ "$i" -le "$n" ]; do
      skills_conf_delete "$(skills_roster_field "$(skills_roster_record "$roster" "$i")" 1)"
      i=$((i + 1))
    done
  fi
}

# Installed = every roster repo has a saved line and its selection is present
# in the store ("*": at least one lock entry for the repo). A repo whose
# agent dir is missing counts as satisfied (it is skipped by reconcile too).
skills_unit_installed() { # unit roster
  local roster="$2" n i rec repo agents saved name
  n="$(skills_roster_count "$roster")"
  i=1
  while [ "$i" -le "$n" ]; do
    rec="$(skills_roster_record "$roster" "$i")"
    i=$((i + 1))
    repo="$(skills_roster_field "$rec" 1)"
    agents="$(skills_roster_field "$rec" 2)"
    saved="$(skills_conf_get "$repo")" || return 1
    if ! skills_agents_ready "$agents"; then continue; fi
    if [ "$saved" = "*" ]; then
      if [ -z "$(skills_lock_names "$repo")" ]; then return 1; fi
    else
      for name in $saved; do
        if [ ! -d "$SKILLS_STORE/$name" ]; then return 1; fi
      done
    fi
  done
  return 0
}
```

- [ ] **Step 4: Source the engine from both entry points**

`run.sh` — after line 72 (`. "$REPO_ROOT/lib/drivers.sh"`) add:
```bash
# shellcheck source=lib/skills.sh
. "$REPO_ROOT/lib/skills.sh"
```
`update.sh` — after line 19 (`. "$REPO_ROOT/lib/drivers.sh"`) add the same two lines. Match the surrounding `# shellcheck source=` comment style already used there.

- [ ] **Step 5: Run the test**

Run: `/bin/bash tests/test_skills_unit.sh`
Expected: `test_skills_unit.sh: 33 passed, 0 failed`. If the interactive cases hang, a prompt is reading from a heredoc-fed loop — check that no `while read <<<` wraps a call to `skills_select_repo`.

- [ ] **Step 6: Lint, full suite, commit**

Run: `tests/run.sh`
```bash
git add lib/skills.sh run.sh update.sh tests/test_skills_unit.sh
git commit -m "feat(skills): unit install/update/uninstall/installed with per-repo selection"
```

---

### Task 7: Units — rewrite `agent-skills`, add `agent-skill-suites`

**Files:**
- Rewrite: `apps/agent-skills.sh`
- Create: `apps/agent-skill-suites.sh`
- Test: `tests/test_units.sh`

**Interfaces:**
- Consumes: `skills_unit_*`.
- Produces: units discoverable by `discover_apps` with ids `agent-skills` and `agent-skill-suites`.

- [ ] **Step 1: Write the failing test**

`tests/test_units.sh`:
```bash
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
APP_NAME="something else"
screen="$(NON_INTERACTIVE=0 DRY_RUN=1 printf '\n' | agent_skill_suites_update 2>&1 >/dev/null || true)"
assert_not_contains "$screen" "something else" "unit does not use APP_NAME at call time"

# dry-run of the real rosters against the fake CLI (fixtures absent -> star repos
# still emit add; explicit repos emit add with their names)
out="$(DRY_RUN=1 agent_skill_suites_install 2>/dev/null)"
assert_contains "$out" "[dry-run] npx -y skills add obra/superpowers -g -y -a codex -s *" "superpowers dry-run add"
assert_contains "$out" "[dry-run] npx -y skills add NeoLabHQ/context-engineering-kit -g -y -s context-engineering" "cek dry-run add"
finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/test_units.sh`
Expected: FAILs on discovery of `agent-skill-suites`, name, note, roster variables.

- [ ] **Step 3: Rewrite `apps/agent-skills.sh`**

```bash
#!/bin/bash
# shellcheck disable=SC2034
# Curated task-pack skills — installed globally via the skills.sh CLI (npx
# skills) into ~/.agents/skills and linked into every configured agent.
# One roster record per upstream repo: owner/repo|agents|default-skills.
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
```

- [ ] **Step 4: Create `apps/agent-skill-suites.sh`**

```bash
#!/bin/bash
# shellcheck disable=SC2034
# Workflow skill suites — superpowers, mattpocock/skills, gsd-pi and the
# context-engineering-kit — installed via the skills.sh CLI (npx skills)
# into ~/.agents/skills. Same roster format and mechanics as agent-skills
# (see lib/skills.sh); the split exists so the two sets can be selected
# independently.
#
# superpowers is linked into Codex only: Claude Code gets it from the
# superpowers plugin (apps/claude-plugins.sh), whose SessionStart hook is
# what makes it fire automatically; a second copy under ~/.claude/skills
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
```

- [ ] **Step 5: Run the test**

Run: `/bin/bash tests/test_units.sh`
Expected: `test_units.sh: 24 passed, 0 failed`.

- [ ] **Step 6: Dry-run the entry points**

```bash
./update.sh --dry-run 2>&1 | grep -A3 "Agent skills"
```
Expected: the task-packs unit prints `[dry-run] npx -y skills add softaworks/agent-toolkit -g -y -s agent-md-refactor ...` for each repo (first run has no `skills.conf`, so defaults apply) and `[dry-run] save skill selection ...` lines; no prompt; exit 0. The suites unit is not in the saved app selection yet, so it does not appear.

- [ ] **Step 7: Lint and commit**

Run: `tests/run.sh`
```bash
git add apps/agent-skills.sh apps/agent-skill-suites.sh tests/test_units.sh
git commit -m "feat(agent-skills): roster units with per-repo selection; add agent-skill-suites"
```

---

### Task 8: Plugins roster and docs

**Files:**
- Modify: `apps/claude-plugins.sh:3,16`, `README.md` (rows 81–83 and the agent-tooling paragraph at ~97–104), `docs/howto.md` (`## agent-skills` section, ~136–146)

- [ ] **Step 1: Drop mattpocock-skills from the plugins roster**

In `apps/claude-plugins.sh` line 16, remove the token `mattpocock-skills@claude-plugins-official ` from `CLAUDE_PLUGINS`. In the header comment on line 3 change `the 12-plugin roster from 9 marketplaces` to `the 11-plugin roster from 9 marketplaces`. Verify:
```bash
grep -c mattpocock apps/claude-plugins.sh     # 0
```

- [ ] **Step 2: README app table**

Replace the three rows:
```markdown
| `claude-plugins` | Claude Code plugins (11 from 9 marketplaces) | `claude plugin` CLI; needs `claude-code` |
| `gsd` | GSD skill suite (67 `gsd-*` skills) | npm `get-shit-done-cc` (installs Node if needed) |
| `agent-skills` | Agent skills, curated task packs (6 repos: softaworks/agent-toolkit, composio, coreyhaines31/marketingskills, lyndonkl/claude, alirezarezvani/claude-skills, ComposioHQ/awesome-claude-skills) | skills.sh CLI (`npx skills`); per-repo checklist on first install, saved in `~/.mac-bootstrap/skills.conf`; roster in `apps/agent-skills.sh` |
| `agent-skill-suites` | Agent skill suites (obra/superpowers → Codex only, mattpocock/skills, open-gsd/gsd-pi, NeoLabHQ/context-engineering-kit) | skills.sh CLI; same checklist/selection model; `*` selections track upstream additions and removals; roster in `apps/agent-skill-suites.sh` |
```

- [ ] **Step 3: README agent-tooling paragraph**

Replace the paragraph beginning `The three agent-tooling units mirror the inventory` (through `are synced manually, not managed here.`) with:
```markdown
The agent-tooling units (`claude-plugins`, `gsd`, `agent-skills`,
`agent-skill-suites`) mirror the inventory in
`claude-nyamaste-studios-strategy/tech/skills.md`. Both skills units are
rosters over the skills.sh CLI: on first install `run.sh` shows one checklist
per upstream repo (pre-checked with the roster defaults), saves the choice per
machine in `~/.mac-bootstrap/skills.conf`, and reconciles the shared store
`~/.agents/skills` against it — selected skills are (re)installed by name,
deselected ones removed, using the CLI's own lock file as the record of what
came from where. Later `run.sh` passes ask once per unit whether to reselect
(Enter = no); `update.sh` never prompts. Checking every skill of a repo saves
`*`, which also picks up skills the repo adds later. Nothing in the store is
hand-copied any more: the old local-only sets were either reinstalled from
their upstreams or removed (see the 2026-09-08 spec).
```

- [ ] **Step 4: howto section**

Replace `## agent-skills` (title through the `-s` bullet) with:
```markdown
## agent-skills / agent-skill-suites

- Both units install through the skills.sh CLI (`npx -y skills`) into the
  shared store `~/.agents/skills`, linked into every detected agent
  (`~/.claude/skills`, `~/.codex/skills`). Node is installed first if `npx`
  is missing.
- **Choosing skills.** First install in an interactive `./run.sh` shows a
  checklist per repo: toggle numbers, `a` = all, `n` = none, Enter confirms.
  Checking every skill saves `*` ("track all": new upstream skills arrive on
  the next update, removed ones are cleaned out). Anything else saves an
  explicit list that only changes when you reselect. Non-interactive first
  installs take the roster defaults.
- **Reselecting.** Later interactive `./run.sh` passes ask
  `Reselect skills for <unit>? [y/N]` once per unit; Enter skips. Skills new
  upstream since your last explicit selection are tagged `(new)`.
  `./update.sh` never prompts.
- **Where it is saved.** `~/.mac-bootstrap/skills.conf`, one `SKILLS_<repo>`
  line per repo. Editing it by hand and running `./update.sh` is a valid way
  to change a selection on a headless machine.
- **superpowers** is linked into Codex only: Claude Code keeps the
  `superpowers` plugin (its SessionStart hook is what makes it fire), and a
  store copy under `~/.claude/skills` would list every skill twice. If
  `~/.codex/skills` does not exist yet, the repo is skipped and installed on
  the next update.
- **mattpocock-skills plugin.** Replaced by the suites unit on 2026-09-08
  (the plugin was skills-only). On a machine that still has it:
  `claude plugin uninstall mattpocock-skills@claude-plugins-official`.
- Removing a unit removes only the skills the lock file attributes to its
  repos; `zap` also forgets its `skills.conf` lines. Skills from other
  sources are never touched, and the units never run a bare `skills update`.
- The CLI takes space-separated names after `-s`, not a comma list.
```
Also update the howto table of contents near the top: the `agent-skills` link becomes `- [agent-skills / agent-skill-suites](#agent-skills--agent-skill-suites)`.

- [ ] **Step 5: Verify and commit**

```bash
grep -n "local-only\|Local-only\|graphify\|awesome-claude-skills copies" README.md docs/howto.md apps/*.sh   # only the spec should mention these now
tests/run.sh
git add apps/claude-plugins.sh README.md docs/howto.md
git commit -m "docs: per-repo skill selection; drop mattpocock-skills plugin from the roster"
```

---

### Task 9: Live migration and verification on this machine

**Files:** none (verification); spec status line update at the end.

- [ ] **Step 1: Uninstall the mattpocock plugin (one-time)**

```bash
claude plugin uninstall mattpocock-skills@claude-plugins-official
claude plugin list 2>/dev/null | grep -c mattpocock     # 0
```

- [ ] **Step 2: Dry-run the full reconcile with the suites unit added**

```bash
sel="$(. lib/common.sh; load_config; printf '%s' "$SELECTED" | tr ' ' ',' | sed 's/^,//')"
./run.sh --dry-run --non-interactive --apps "$sel,agent-skill-suites" 2>&1 | grep -E "dry-run\] npx|dry-run\] save skill|removing untracked|Agent skill"
```
Expected: for `agent-skills`, adds for the six repos with their default names (including `ComposioHQ/awesome-claude-skills ... youtube-downloader`); for `agent-skill-suites`, `add obra/superpowers -g -y -a codex -s *`, `add mattpocock/skills -g -y -s *`, `add open-gsd/gsd-pi -g -y -s *`, `add NeoLabHQ/context-engineering-kit -g -y -s context-engineering ...`; `save skill selection` lines for all ten repos; no prompts.

- [ ] **Step 3: Live non-interactive install**

```bash
./run.sh --non-interactive --apps "$sel,agent-skill-suites" 2>&1 | tail -40
```
Expected: exit 0; summary lists `agent-skill-suites` under installed and `agent-skills` under updated.

- [ ] **Step 4: Verify state**

```bash
cat ~/.mac-bootstrap/skills.conf
ls ~/.agents/skills | wc -l                       # 30 softaworks + 1 composio + 10 + 10 + 6 + 19 + 37 mattpocock + 1 gsd + 22 cek + 14 superpowers ≈ 150
ls ~/.codex/skills | grep -c -E '^(brainstorming|writing-plans)$'     # 2  (superpowers reached Codex)
ls ~/.claude/skills | grep -c -E '^(brainstorming|writing-plans)$'    # 0  (not duplicated in Claude Code)
ls ~/.agents/skills | grep -c -E '^(graphify|video-downloader|caveman)$'   # 0
python3 -c "import json,collections;d=json.load(open('$HOME/.agents/.skill-lock.json'))['skills'];print(collections.Counter(v['source'] for v in d.values()))"
```
Expected sources: the ten roster repos and nothing else. Note the actual store count in the commit message.

- [ ] **Step 5: update.sh does not prompt and returns 0**

```bash
./update.sh 2>&1 | grep -E "Agent skill|Reselect|updated:|failed:"
```
Expected: both units listed under `updated:`; no `Reselect` line.

- [ ] **Step 6: Interactive reselect — user-driven**

Hand off to the user: run `./run.sh`, keep the app selection (Enter), answer `y` to `Reselect skills for Agent skill suites?`, uncheck one context-engineering-kit skill, Enter through the rest. Then confirm:
```bash
grep context_engineering_kit ~/.mac-bootstrap/skills.conf     # 21 names
ls ~/.agents/skills | grep -c <unchecked-name>                 # 0
```

- [ ] **Step 7: Mark the spec implemented and commit**

Edit the spec's status line to `**Status: implemented 2026-09-08 (rev 2).**` and add one line under Background with the measured store count and anything the live run changed.
```bash
git add docs/superpowers/specs/2026-09-08-agent-skill-selection-design.md
git commit -m "docs(spec): mark agent skill selection implemented"
git push origin main
```

---

## Self-review against the spec

- Roster format, `*` semantics, purge lists, unit names, sixth repo, 22-skill default, codex-only superpowers, skip-when-agent-dir-missing, `installed` rules, keep/zap, dry-run, offline fallback, python3-missing warning, no bare update, install-then-update double-call, `(new)` tags, dropped-upstream warning, header-line "saved as *": each maps to Tasks 2–7 with a test. Docs: Task 8. Live checks 1–8 from the spec's Testing section: Task 9 (item 4 "plant an untracked copy" is covered by the purge unit tests in Tasks 5 and 6 rather than live).
- Names used consistently: `skills_conf_get/put/delete`, `skills_list_upstream`, `skills_upstream_names`, `skills_parse_listing`, `skills_lock_names`, `skills_lock_has`, `skills_agent_dir`, `skills_agents_ready`, `skills_roster_count/record/field`, `skills_reconcile`, `skills_purge_untracked`, `skills_interactive`, `skills_select_repo`, `skills_unit_sync/install/update/uninstall/installed`, `select_from_list`, `SKILLS_SYNCED_UNITS`, `AGENT_SKILLS_UNIT/ROSTER/PURGE`, `AGENT_SKILL_SUITES_UNIT/ROSTER/PURGE`.
- Known judgment call left to the implementer: exact assertion counts in "Expected" lines are approximate; the pass/fail split is what matters.
