# VS Code, Gemini Skills and Managed MCP Servers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Manage VS Code as an app that installs each agent's extension, link the shared skills store into Gemini CLI, and apply a repo-owned MCP server roster to Claude Code, Codex and Gemini CLI so all three agents have the same skills and MCP servers in the terminal and inside VS Code.

**Architecture:** Three additions in the repo's existing unit pattern. A `vscode` cask unit plus a small VS Code driver in `lib/drivers.sh` installs extensions for whichever agent CLIs are installed. The skills engine `lib/skills.sh` learns a third agent, `gemini-cli`. A new engine `lib/mcp.sh` applies the roster `dotfiles/mcp-servers.conf` through each CLI's own `mcp add`/`mcp remove`, tracking what it applied in `$CONFIG_DIR/mcp.conf`; the `mcp-servers` unit is data plus the `github-mcp-server` formula, and `bin/github-mcp.sh` launches that server with a token from `gh`.

**Tech Stack:** bash 3.2 (stock macOS `/bin/bash`), python3 for JSON, awk for the TSV state file, Homebrew casks/formulas, the `claude`/`codex`/`gemini` CLIs' `mcp` subcommands, VS Code's `code` CLI, shellcheck.

**Spec:** `docs/superpowers/specs/2026-09-10-vscode-agents-mcp-design.md`

## Global Constraints

- **bash 3.2 compatible.** No `mapfile`/`readarray`, no associative arrays, no `${var,,}`, no `;&`. Guard empty-array expansion with `${arr[@]+"${arr[@]}"}`. Run tests with `/bin/bash` (`tests/run.sh` does).
- **Every mutating command goes through `run_cmd`** (from `lib/common.sh`) so `--dry-run` prints it instead. State-file writes are skipped under `DRY_RUN=1`.
- **No `log` (stdout) inside any function whose stdout is captured with `$(...)`.** Use `warn`/`err` (stderr) there.
- **Unit files must not reference `$APP_NAME` inside functions** — `discover_apps` resets it before sourcing each app.
- **Only names recorded in the MCP state file are ever removed from an agent.** A server the user added themselves is never touched, even if the roster later uses the same name.
- **Unit id `mcp-servers`** (not `agent-mcp`): `apps/*.sh` load alphabetically and this id must sort after `claude-code`, `codex`, `gemini-cli` and before `vscode`. A test asserts it.
- Extension IDs, verbatim: `anthropic.claude-code`, `openai.chatgpt`, `google.gemini-cli-vscode-ide-companion`, `google.geminicodeassist`.
- Per-agent MCP command shapes (stdio uses `--` before the command in all three CLIs):
  - claude: `claude mcp add -s user NAME -- CMD ARGS` / `claude mcp add -s user --transport http NAME URL` / `claude mcp get NAME` / `claude mcp remove -s user NAME`; binary is `~/.local/bin/claude`.
  - codex: `codex mcp add NAME -- CMD ARGS` / `codex mcp add NAME --url URL` / `codex mcp get NAME` / `codex mcp remove NAME`.
  - gemini: `gemini mcp add -s user NAME -- CMD ARGS` / `gemini mcp add -s user -t http NAME URL` / presence read from `~/.gemini/settings.json` `.mcpServers` / `gemini mcp remove -s user NAME`.
- Roster record: `name|transport|command-or-url [args...]`; `transport` ∈ {`stdio`,`http`}; name matches `^[A-Za-z0-9_-]+$`; a leading `~/` in the target expands to `$HOME` at apply time.
- GitHub toolsets: `repos,issues,pull_requests` (spec Decision 6).
- Conventional Commits; commit after every task. Direct to `main` (repo workflow).
- Paths: config dir `$CONFIG_DIR` (`~/.mac-bootstrap`, `BOOTSTRAP_CONFIG_DIR` in tests); MCP state `$CONFIG_DIR/mcp.conf`; roster `$REPO_ROOT/dotfiles/mcp-servers.conf` (`MCP_ROSTER_FILE` overridable).

---

## File map

| File | Responsibility |
|---|---|
| `lib/skills.sh` (modify) | Add `gemini-cli` agent: dir `~/.gemini/skills`, home `~/.gemini`, in `SKILLS_KNOWN_AGENTS`; purge also cleans `~/.gemini/skills` |
| `apps/gemini-cli.sh` (modify) | Create `~/.gemini/skills` on install/update; zap removes `~/.gemini` |
| `lib/drivers.sh` (modify) | VS Code driver: `vscode_code_bin`, `vscode_ext_installed`, `vscode_ext_install` |
| `apps/vscode.sh` (create) | `vscode` unit: cask + `VSCODE_AGENT_EXTENSIONS` mapping + `vscode_extensions_apply` |
| `lib/mcp.sh` (create) | MCP engine: roster parsing, per-agent add/has/remove, TSV state, `mcp_apply`, `mcp_remove_all` |
| `dotfiles/mcp-servers.conf` (create) | The roster: context7, github |
| `apps/mcp-servers.sh` (create) | `mcp-servers` unit: `github-mcp-server` formula + `mcp_apply`/`mcp_remove_all` |
| `bin/github-mcp.sh` (create) | GitHub MCP launcher; token from `gh auth token`; limited toolsets |
| `install.sh` (modify) | Symlink `bin/github-mcp.sh` into `~/.local/bin` |
| `run.sh`, `update.sh` (modify) | Source `lib/mcp.sh` after `lib/skills.sh` |
| `tests/lib.sh` (modify) | Sandbox gains `~/.gemini/skills`, fake-code and fake-mcp env, sources `lib/mcp.sh` |
| `tests/fakes/npx` (modify) | Links into `~/.gemini/skills` for agent `gemini-cli`; default agents include it |
| `tests/fakes/code` (create) | Fake VS Code CLI |
| `tests/fakes/fake-mcp-cli`, `tests/fakes/claude`, `tests/fakes/codex`, `tests/fakes/gemini` (create) | Fake agent CLIs for `mcp get/add/remove` |
| `tests/test_skills_reconcile.sh`, `tests/test_skills_unit.sh` (modify) | `-a` lists gain `gemini-cli` |
| `tests/test_vscode.sh`, `tests/test_mcp.sh`, `tests/test_github_mcp.sh` (create) | New coverage |
| `tests/test_units.sh` (modify) | Discovery, categories, alphabetical position of `mcp-servers` |
| `tests/run.sh` (modify) | shellcheck the new fakes and `bin/github-mcp.sh` |
| `README.md`, `docs/howto.md` (modify) | Tables, agent dirs, new sections |
| spec (modify) | Status line → implemented |

---

### Task 1: Gemini CLI joins the skills engine

**Files:**
- Modify: `lib/skills.sh` (functions `skills_agent_dir`, `skills_agent_home`, variable `SKILLS_KNOWN_AGENTS`, function `skills_purge_untracked`)
- Modify: `apps/gemini-cli.sh`
- Modify: `tests/lib.sh` (`setup_sandbox`), `tests/fakes/npx` (`agent_dir`, default `agents`, `remove`)
- Modify: `tests/test_skills_reconcile.sh`, `tests/test_skills_unit.sh`

**Interfaces:**
- Produces: `skills_agent_dir gemini-cli` → `$HOME/.gemini/skills`; `skills_agent_home gemini-cli` → `$HOME/.gemini`; `SKILLS_KNOWN_AGENTS="claude-code codex gemini-cli"`.

- [ ] **Step 1: Update the test sandbox and the fake npx**

In `tests/lib.sh`, `setup_sandbox`, change the mkdir line to:

```bash
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"
```

In `tests/fakes/npx`, replace the `agent_dir` line with:

```bash
agent_dir() { case "$1" in codex) printf '%s/.codex/skills\n' "$HOME" ;; gemini-cli) printf '%s/.gemini/skills\n' "$HOME" ;; *) printf '%s/.claude/skills\n' "$HOME" ;; esac; }
```

Change the default `agents="claude-code codex"` (inside `add)`) to `agents="claude-code codex gemini-cli"`, and in the `remove)` arm change the `rm -rf` line to:

```bash
      rm -rf "${store:?}/$name" "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name" "$HOME/.gemini/skills/$name"
```

- [ ] **Step 2: Update the existing assertions to the three-agent list and add a Gemini link check**

`tests/test_skills_reconcile.sh`:
- line 11: `"skills add acme/tools -g -y -a claude-code codex gemini-cli -s alpha beta"`
- after line 11 add: `assert_ok "linked into gemini" test -L "$HOME/.gemini/skills/alpha"`
- line 26: `"skills add acme/tools -g -y -a claude-code codex gemini-cli -s *"`
- line 32: `assert_eq "claude-code codex gemini-cli" "$(skills_installed_agents)" "all agent homes present"`
- line 35: `assert_eq "claude-code gemini-cli" "$(skills_installed_agents)" "codex home missing -> claude-code and gemini-cli"`
- line 37: `"skills add acme/suite -g -y -a claude-code gemini-cli -s one"`
- line 65: `"[dry-run] npx -y skills add acme/suite -g -y -a claude-code codex gemini-cli -s two"`

`tests/test_skills_unit.sh` line 29: `"add acme/tools -g -y -a claude-code codex gemini-cli -s beta"`.

- [ ] **Step 3: Run the two test files to verify they fail**

Run: `/bin/bash tests/test_skills_reconcile.sh; /bin/bash tests/test_skills_unit.sh`
Expected: FAIL on "add command shape" (still `-a claude-code codex`), "linked into gemini", "all agent homes present".

- [ ] **Step 4: Implement in `lib/skills.sh`**

```bash
skills_agent_dir() {
  case "$1" in
    codex) printf '%s/.codex/skills\n' "$HOME" ;;
    claude | claude-code) printf '%s/.claude/skills\n' "$HOME" ;;
    gemini | gemini-cli) printf '%s/.gemini/skills\n' "$HOME" ;;
    *) printf '%s/.%s/skills\n' "$HOME" "$1" ;;
  esac
}

# The agent's home dir — proof the agent is installed. (Codex reads the shared
# store ~/.agents/skills directly; the CLI creates no links under
# ~/.codex/skills, so that dir is not a usable readiness signal. Gemini CLI
# reads ~/.gemini/skills, which apps/gemini-cli.sh creates on install.)
skills_agent_home() {
  case "$1" in
    codex) printf '%s/.codex\n' "$HOME" ;;
    claude | claude-code) printf '%s/.claude\n' "$HOME" ;;
    gemini | gemini-cli) printf '%s/.gemini\n' "$HOME" ;;
    *) printf '%s/.%s\n' "$HOME" "$1" ;;
  esac
}
```

Change `SKILLS_KNOWN_AGENTS="claude-code codex"` to `SKILLS_KNOWN_AGENTS="claude-code codex gemini-cli"`.

In `skills_purge_untracked`, change the `for d in` line to:

```bash
    for d in "$SKILLS_STORE/$name" "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name" "$HOME/.gemini/skills/$name"; do
```

- [ ] **Step 5: Make the gemini-cli unit create the skills dir**

Replace `apps/gemini-cli.sh` with:

```bash
#!/bin/bash
# shellcheck disable=SC2034
# Google Gemini CLI — Homebrew formula. Creates ~/.gemini/skills so the skills
# units (lib/skills.sh, agent gemini-cli) can link into it on the same run;
# Gemini CLI reads that directory natively (`gemini skills list`).
APP_NAME="Gemini CLI"
APP_CATEGORY="AI"

gemini_cli_skills_dir() { run_cmd mkdir -p "$HOME/.gemini/skills"; }

gemini_cli_install()   { formula_install gemini-cli && gemini_cli_skills_dir; }
gemini_cli_update()    { formula_update gemini-cli && gemini_cli_skills_dir; }
# keep leaves ~/.gemini (settings, skills links, MCP config); zap removes it.
gemini_cli_uninstall() {
  formula_uninstall gemini-cli "$1" || return 1
  if [ "${1:-keep}" = zap ]; then run_cmd rm -rf "$HOME/.gemini"; fi
}
gemini_cli_installed() { formula_installed gemini-cli; }
```

- [ ] **Step 6: Run the whole suite**

Run: `tests/run.sh`
Expected: all test files report `0 failed`; shellcheck clean.

- [ ] **Step 7: Commit**

```bash
git add lib/skills.sh apps/gemini-cli.sh tests/lib.sh tests/fakes/npx tests/test_skills_reconcile.sh tests/test_skills_unit.sh
git commit -m "feat(skills): link the shared skills store into Gemini CLI"
```

---

### Task 2: VS Code driver in `lib/drivers.sh`

**Files:**
- Modify: `lib/drivers.sh` (append a section before `# ---- macOS preferences`)
- Create: `tests/fakes/code`
- Modify: `tests/lib.sh` (`setup_sandbox`)
- Create: `tests/test_vscode.sh` (driver half; Task 3 extends it)

**Interfaces:**
- Produces: `vscode_code_bin` (prints path, rc 1 if none); `vscode_ext_installed ID [LOWERCASE_LIST]` (rc 0/1); `vscode_ext_install ID` (via `run_cmd`).

- [ ] **Step 1: Create the fake `code` CLI**

`tests/fakes/code`:

```bash
#!/bin/bash
# Fake VS Code `code` CLI for tests. Logs each call (args as given) to
# $FAKE_CODE_LOG and keeps the installed-extension list in
# $FAKE_CODE_EXTENSIONS (one id per line, lowercased like the real CLI):
#   --list-extensions        print the list
#   --install-extension ID   append ID
# FAKE_CODE_FAIL=1 makes --install-extension exit 1.
set -u
printf '%s\n' "$*" >>"${FAKE_CODE_LOG:?}"
case "${1:-}" in
  --list-extensions)
    if [ -f "${FAKE_CODE_EXTENSIONS:?}" ]; then cat "$FAKE_CODE_EXTENSIONS"; fi
    ;;
  --install-extension)
    if [ "${FAKE_CODE_FAIL:-0}" = 1 ]; then exit 1; fi
    printf '%s\n' "$2" | tr '[:upper:]' '[:lower:]' >>"${FAKE_CODE_EXTENSIONS:?}"
    ;;
  *) echo "fake code: unsupported invocation: $*" >&2; exit 2 ;;
esac
```

`chmod +x tests/fakes/code`.

In `tests/lib.sh` `setup_sandbox`, after the `FAKE_NPX_FIXTURES` line add:

```bash
  export FAKE_CODE_LOG="$SANDBOX/code.log"
  export FAKE_CODE_EXTENSIONS="$SANDBOX/code-extensions"
  : >"$FAKE_CODE_LOG"
  : >"$FAKE_CODE_EXTENSIONS"
```

(The shellcheck list in `tests/run.sh` is extended once, in Task 6, when every new file exists. Until then run `shellcheck tests/fakes/code` by hand.)

- [ ] **Step 2: Write the failing driver tests**

`tests/test_vscode.sh`:

```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
discover_apps
code_log() { cat "$FAKE_CODE_LOG"; }

# ---- driver ----
assert_eq "$TESTS_DIR/fakes/code" "$(vscode_code_bin)" "code CLI resolved from PATH"
printf 'Anthropic.claude-code\n' >"$FAKE_CODE_EXTENSIONS"
assert_ok "installed, case-insensitive" vscode_ext_installed anthropic.claude-code
assert_fail "not installed" vscode_ext_installed openai.chatgpt
assert_ok "cached list honoured" vscode_ext_installed openai.chatgpt "openai.chatgpt"
assert_fail "cached list is authoritative" vscode_ext_installed anthropic.claude-code "openai.chatgpt"
: >"$FAKE_CODE_LOG"
vscode_ext_install openai.chatgpt
assert_contains "$(code_log)" "--install-extension openai.chatgpt" "install calls the CLI"
assert_ok "installed after install" vscode_ext_installed openai.chatgpt
out="$(DRY_RUN=1 vscode_ext_install google.geminicodeassist)"
assert_contains "$out" "[dry-run] $TESTS_DIR/fakes/code --install-extension google.geminicodeassist" "dry-run install prints"
assert_fail "dry-run did not install" vscode_ext_installed google.geminicodeassist

finish
```

- [ ] **Step 3: Run to verify failure**

Run: `/bin/bash tests/test_vscode.sh`
Expected: FAIL — `vscode_code_bin: command not found` and following.

- [ ] **Step 4: Implement the driver**

Append to `lib/drivers.sh` before the `# ---- macOS preferences` section:

```bash
# ---- VS Code extensions ------------------------------------------------------

# The visual-studio-code cask links `code` into the brew prefix; a PATH without
# Homebrew (GUI-launched shells) still has the copy inside the app bundle.
vscode_code_bin() {
  local b="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if command -v code >/dev/null 2>&1; then
    command -v code
    return 0
  fi
  if [ -x "$b" ]; then
    printf '%s\n' "$b"
    return 0
  fi
  return 1
}

# vscode_ext_installed id [list]: 0 when the extension is installed. `code
# --list-extensions` prints ids lowercased; pass its (lowercased) output as
# $2 to avoid one CLI call per id.
vscode_ext_installed() {
  local id list code
  id="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  if [ -n "${2+x}" ]; then
    list="$2"
  else
    code="$(vscode_code_bin)" || return 1
    list="$("$code" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  fi
  printf '%s\n' "$list" | grep -qx "$id"
}

vscode_ext_install() {
  local code
  if ! code="$(vscode_code_bin)"; then
    err "VS Code: 'code' CLI not found — cannot install extension $1"
    return 1
  fi
  run_cmd "$code" --install-extension "$1"
}
```

- [ ] **Step 5: Run to verify pass**

Run: `/bin/bash tests/test_vscode.sh`
Expected: `test_vscode.sh: 9 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add lib/drivers.sh tests/fakes/code tests/lib.sh tests/test_vscode.sh
git commit -m "feat(drivers): VS Code extension driver with a fake code CLI for tests"
```

---

### Task 3: `vscode` unit with the agent-extension pass

**Files:**
- Create: `apps/vscode.sh`
- Modify: `tests/test_vscode.sh` (append), `tests/test_units.sh` (append)

**Interfaces:**
- Consumes: `vscode_code_bin`, `vscode_ext_installed`, `vscode_ext_install` (Task 2); `app_fn` from `lib/common.sh`; `<unit>_installed` functions from `discover_apps`.
- Produces: `VSCODE_AGENT_EXTENSIONS` (records `unit|ext ext`), `vscode_extensions_apply` (rc 1 if any install failed), `vscode_install/_update/_uninstall/_installed`.

- [ ] **Step 1: Append the failing unit tests**

Append to `tests/test_vscode.sh` before `finish`:

```bash
# ---- unit: mapping ----
assert_eq "3" "$(printf '%s\n' "$VSCODE_AGENT_EXTENSIONS" | grep -c '|')" "three agents mapped"
assert_contains "$VSCODE_AGENT_EXTENSIONS" "claude-code|anthropic.claude-code" "claude mapping"
assert_contains "$VSCODE_AGENT_EXTENSIONS" "codex|openai.chatgpt" "codex mapping"
assert_contains "$VSCODE_AGENT_EXTENSIONS" "gemini-cli|google.gemini-cli-vscode-ide-companion google.geminicodeassist" "gemini gets both extensions"

# ---- unit: apply installs only for installed agents ----
claude_code_installed() { return 0; }
codex_installed() { return 1; }
gemini_cli_installed() { return 0; }
: >"$FAKE_CODE_EXTENSIONS"
: >"$FAKE_CODE_LOG"
assert_ok "apply succeeds" vscode_extensions_apply
assert_contains "$(code_log)" "--install-extension anthropic.claude-code" "claude ext installed"
assert_not_contains "$(code_log)" "openai.chatgpt" "codex not installed -> no ext"
assert_contains "$(code_log)" "--install-extension google.gemini-cli-vscode-ide-companion" "gemini companion installed"
assert_contains "$(code_log)" "--install-extension google.geminicodeassist" "gemini code assist installed"
assert_eq "1" "$(grep -c -- '--list-extensions' "$FAKE_CODE_LOG")" "listing read once per pass"

# second pass: everything present, nothing installed
: >"$FAKE_CODE_LOG"
vscode_extensions_apply
assert_not_contains "$(code_log)" "--install-extension" "present extensions not reinstalled"

# a failed install is reported, the pass continues, rc is 1
: >"$FAKE_CODE_EXTENSIONS"
: >"$FAKE_CODE_LOG"
export FAKE_CODE_FAIL=1
assert_fail "failed install returns 1" vscode_extensions_apply
assert_eq "3" "$(grep -c -- '--install-extension' "$FAKE_CODE_LOG")" "keeps going after a failure"
unset FAKE_CODE_FAIL

# dry-run prints the installs and changes nothing
: >"$FAKE_CODE_LOG"
out="$(DRY_RUN=1 vscode_extensions_apply)"
assert_contains "$out" "[dry-run] $TESTS_DIR/fakes/code --install-extension anthropic.claude-code" "dry-run prints install"
assert_not_contains "$(code_log)" "--install-extension" "dry-run installs nothing"

# without a code CLI: dry-run explains, real run fails
vscode_code_bin() { return 1; }
out="$(DRY_RUN=1 vscode_extensions_apply)"
assert_contains "$out" "[dry-run] install agent extensions once VS Code is present" "dry-run without VS Code"
assert_fail "no code CLI -> rc 1" vscode_extensions_apply
```

Append to `tests/test_units.sh` before `finish` (the file's existing helpers `has`, `app_name_for` stay):

```bash
# vscode + mcp-servers units
idx_of() { local i=0; while [ "$i" -lt "${#APP_IDS[@]}" ]; do if [ "${APP_IDS[$i]}" = "$1" ]; then printf '%s\n' "$i"; return; fi; i=$((i + 1)); done; printf -- '-1\n'; }
cat_for() { local i; i="$(idx_of "$1")"; [ "$i" -ge 0 ] && printf '%s\n' "${APP_CATEGORIES[$i]}"; }
assert_ok "vscode discovered" has vscode
assert_eq "Visual Studio Code" "$(app_name_for vscode)" "vscode name"
assert_eq "Development" "$(cat_for vscode)" "vscode category"
assert_ok "mcp-servers discovered" has mcp-servers
assert_eq "AI" "$(cat_for mcp-servers)" "mcp-servers category"
# apps load alphabetically; mcp-servers must come after the agent CLIs and before vscode
assert_ok "gemini-cli before mcp-servers" test "$(idx_of gemini-cli)" -lt "$(idx_of mcp-servers)"
assert_ok "codex before mcp-servers" test "$(idx_of codex)" -lt "$(idx_of mcp-servers)"
assert_ok "claude-code before mcp-servers" test "$(idx_of claude-code)" -lt "$(idx_of mcp-servers)"
assert_ok "mcp-servers before vscode" test "$(idx_of mcp-servers)" -lt "$(idx_of vscode)"
```

(The `mcp-servers` assertions pass only after Task 6; that is expected.)

- [ ] **Step 2: Run to verify failure**

Run: `/bin/bash tests/test_vscode.sh`
Expected: FAIL from "three agents mapped" onward (`VSCODE_AGENT_EXTENSIONS` empty, `vscode_extensions_apply` not found).

- [ ] **Step 3: Create the unit**

`apps/vscode.sh`:

```bash
#!/bin/bash
# shellcheck disable=SC2034
# Visual Studio Code — Homebrew cask (self-updates). Also installs the VS Code
# extension of every managed agent CLI installed on this machine, so Claude
# Code, Codex and Gemini CLI work inside the editor with the same skills and
# MCP servers they have in the terminal: each extension drives the same CLI
# against the same ~/.claude, ~/.codex or ~/.gemini. Extensions update
# themselves inside VS Code; the pass here only fills gaps, on every
# install/update. Deselecting an agent later leaves its extension in place.
APP_NAME="Visual Studio Code"
APP_CATEGORY="Development"
APP_NOTE="Agent extensions (Claude Code, Codex, Gemini CLI Companion + Gemini Code Assist) are installed for whichever of claude-code, codex, gemini-cli is installed; each needs its own sign-in on first use. Deselecting an agent leaves its extension in place. zap removes ~/.vscode (all extensions) and VS Code's user settings."

# agent-unit-id|extension ids (space-separated). Unit ids are the apps/*.sh
# names; <unit>_installed decides whether the extensions are wanted.
VSCODE_AGENT_EXTENSIONS="claude-code|anthropic.claude-code
codex|openai.chatgpt
gemini-cli|google.gemini-cli-vscode-ide-companion google.geminicodeassist"

# Install the missing extensions for every agent whose unit reports
# installed. Keeps going after a failure and returns 1 at the end if any
# install failed. The extension listing is read once per pass.
vscode_extensions_apply() {
  local rc=0 n i rec unit exts ext code list
  if ! code="$(vscode_code_bin)"; then
    if [ "$DRY_RUN" = 1 ]; then
      log "[dry-run] install agent extensions once VS Code is present"
      return 0
    fi
    err "vscode: 'code' CLI not found — cannot install agent extensions"
    return 1
  fi
  list="$("$code" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  # Line-numbered iteration (not `while read`) so the CLI calls inside never
  # compete with the loop for stdin — same rule as lib/skills.sh.
  n="$(printf '%s\n' "$VSCODE_AGENT_EXTENSIONS" | grep -c '|')"
  i=1
  while [ "$i" -le "$n" ]; do
    rec="$(printf '%s\n' "$VSCODE_AGENT_EXTENSIONS" | sed -n "${i}p")"
    i=$((i + 1))
    unit="${rec%%|*}"
    exts="${rec#*|}"
    if ! "$(app_fn "$unit" installed)" >/dev/null 2>&1; then continue; fi
    for ext in $exts; do
      if vscode_ext_installed "$ext" "$list"; then continue; fi
      log "vscode: installing extension $ext (for $unit)"
      if ! vscode_ext_install "$ext"; then
        err "vscode: failed to install extension $ext"
        rc=1
      fi
    done
  done
  return "$rc"
}

vscode_install()   { cask_install visual-studio-code && vscode_extensions_apply; }
vscode_update()    { cask_update visual-studio-code && vscode_extensions_apply; }
vscode_uninstall() { cask_uninstall visual-studio-code "$1"; }
vscode_installed() { cask_installed visual-studio-code; }
```

- [ ] **Step 4: Run to verify pass**

Run: `/bin/bash tests/test_vscode.sh`
Expected: `0 failed`. `/bin/bash tests/test_units.sh` fails only on the `mcp-servers` lines (added in Task 6).

- [ ] **Step 5: Commit**

```bash
git add apps/vscode.sh tests/test_vscode.sh tests/test_units.sh
git commit -m "feat(apps): manage Visual Studio Code and install the agent extensions"
```

---

### Task 4: MCP engine — roster, per-agent commands, detection

**Files:**
- Create: `lib/mcp.sh` (first half), `dotfiles/mcp-servers.conf`
- Create: `tests/fakes/fake-mcp-cli`, `tests/fakes/claude`, `tests/fakes/codex`, `tests/fakes/gemini`
- Modify: `tests/lib.sh` (`setup_sandbox`, `load_libs`), `run.sh:74`, `update.sh:21`
- Create: `tests/test_mcp.sh` (first half)

**Interfaces:**
- Produces: `MCP_ROSTER_FILE`, `MCP_KNOWN_AGENTS="claude codex gemini"`, `mcp_roster_records`, `mcp_record_name/_transport/_target/_valid`, `mcp_agent_ready A`, `mcp_agent_cli A`, `mcp_ready_agents`, `mcp_agent_has A NAME`, `mcp_agent_add A RECORD`, `mcp_agent_remove A NAME`.

- [ ] **Step 1: Create the fake agent CLIs**

`tests/fakes/fake-mcp-cli`:

```bash
#!/bin/bash
# Fake `claude|codex|gemini mcp ...` for tests. $1 is the agent name (passed
# by the tests/fakes/<agent> wrappers), the rest the CLI args. Logs
# "<agent> <args>" to $FAKE_MCP_LOG. The per-agent server list lives in
# $FAKE_MCP_DIR/<agent>, one name per line; the gemini fake also writes a
# real ~/.gemini/settings.json with mcpServers so lib/mcp.sh's JSON detection
# path is exercised.
#   mcp get NAME                 exit 0 if NAME is in the store
#   mcp add [options] NAME ...   add NAME (first positional after the options)
#   mcp remove [options] NAME    remove NAME
#   mcp list                     print the store
# FAKE_MCP_FAIL=1 makes add/remove exit 1.
set -u
agent="$1"
shift
printf '%s %s\n' "$agent" "$*" >>"${FAKE_MCP_LOG:?}"
store="${FAKE_MCP_DIR:?}/$agent"
touch "$store"
if [ "${1:-}" != mcp ]; then echo "fake $agent: unsupported invocation: $*" >&2; exit 2; fi
shift
cmd="${1:-}"
shift || true

name=""
skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in
    -s | --scope | -t | --transport | --url) skip=1 ;;
    --) break ;;
    -*) ;;
    *) name="$a"; break ;;
  esac
done

gemini_sync() {
  if [ "$agent" != gemini ]; then return 0; fi
  mkdir -p "$HOME/.gemini"
  python3 - "$HOME/.gemini/settings.json" "$store" <<'PY'
import json, sys
names = [l.strip() for l in open(sys.argv[2]) if l.strip()]
json.dump({"mcpServers": {n: {"command": "fake"} for n in names}}, open(sys.argv[1], "w"))
PY
}

case "$cmd" in
  get) grep -qx "$name" "$store" ;;
  add)
    if [ "${FAKE_MCP_FAIL:-0}" = 1 ]; then exit 1; fi
    grep -qx "$name" "$store" || printf '%s\n' "$name" >>"$store"
    gemini_sync
    ;;
  remove)
    if [ "${FAKE_MCP_FAIL:-0}" = 1 ]; then exit 1; fi
    grep -vx "$name" "$store" >"$store.tmp" || true
    mv "$store.tmp" "$store"
    gemini_sync
    ;;
  list) cat "$store" ;;
  *) echo "fake $agent: unsupported mcp command: $cmd" >&2; exit 2 ;;
esac
```

`tests/fakes/claude`, `tests/fakes/codex`, `tests/fakes/gemini` (three files, same body except the agent word; they resolve `fake-mcp-cli` through PATH because tests also reach `claude` through a wrapper in the sandbox `~/.local/bin`):

```bash
#!/bin/bash
# Fake agent CLI for tests — see tests/fakes/fake-mcp-cli.
exec fake-mcp-cli claude "$@"
```

(`codex` and `gemini` with their own name.) `chmod +x` all four.

In `tests/lib.sh` `setup_sandbox`, after the fake-code lines add:

```bash
  export FAKE_MCP_LOG="$SANDBOX/mcp.log"
  export FAKE_MCP_DIR="$SANDBOX/mcp"
  : >"$FAKE_MCP_LOG"
  mkdir -p "$FAKE_MCP_DIR"
```

and in `load_libs` append after the skills line:

```bash
  # shellcheck source=/dev/null
  . "$REPO_ROOT/lib/mcp.sh"
```

In `run.sh` after line 74 (`. "$REPO_ROOT/lib/skills.sh"`) and in `update.sh` after line 21 add:

```bash
# shellcheck source=lib/mcp.sh
. "$REPO_ROOT/lib/mcp.sh"
```

- [ ] **Step 2: Create the roster**

`dotfiles/mcp-servers.conf`:

```
# Managed MCP servers — applied by the mcp-servers unit (lib/mcp.sh) to
# Claude Code, Codex and Gemini CLI in user scope through each CLI's own
# `mcp add`. One record per line: name|transport|command-or-url [args...]
#   transport  stdio or http
#   a leading ~/ in the command is expanded to $HOME when applied
# Names: letters, digits, - and _. Adding a server here grows every agent's
# tool list (Claude's per-turn payload included — run claude-context-audit.sh
# after changes). Removing a line removes the server from every agent on the
# next run; servers you added yourself outside this file are never touched.
context7|stdio|npx -y @upstash/context7-mcp
github|stdio|~/.local/bin/github-mcp.sh
```

- [ ] **Step 3: Write the failing tests (first half)**

`tests/test_mcp.sh`:

```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
mcp_log() { cat "$FAKE_MCP_LOG"; }
state() { grep -v '^#' "$(mcp_state_file)" 2>/dev/null; }
# lib/mcp.sh reaches Claude Code through ~/.local/bin/claude (the native
# installer's path); point the sandbox copy at the fake.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/bash\nexec fake-mcp-cli claude "$@"\n' >"$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"

# ---- roster parsing ----
MCP_ROSTER_FILE="$SANDBOX/roster.conf"
printf '# comment\n\ncontext7|stdio|npx -y @upstash/context7-mcp\ngithub|stdio|~/.local/bin/github-mcp.sh\nsentry|http|https://mcp.sentry.dev/mcp\n' >"$MCP_ROSTER_FILE"
assert_eq "3" "$(mcp_roster_records | wc -l | tr -d ' ')" "comments and blanks skipped"
rec="$(mcp_roster_records | sed -n 2p)"
assert_eq "github" "$(mcp_record_name "$rec")" "name field"
assert_eq "stdio" "$(mcp_record_transport "$rec")" "transport field"
assert_eq "$HOME/.local/bin/github-mcp.sh" "$(mcp_record_target "$rec")" "~/ expanded to HOME"
assert_eq "npx -y @upstash/context7-mcp" "$(mcp_record_target "$(mcp_roster_records | sed -n 1p)")" "args kept"
assert_ok "valid record" mcp_record_valid "$rec"
assert_fail "bad name" mcp_record_valid "bad name|stdio|x"
assert_fail "bad transport" mcp_record_valid "x|sse|x"
assert_fail "empty target" mcp_record_valid "x|stdio|"
MCP_ROSTER_FILE="$SANDBOX/missing.conf"
assert_fail "missing roster -> rc 1" mcp_roster_records
MCP_ROSTER_FILE="$SANDBOX/roster.conf"

# ---- agents ----
assert_eq "claude codex gemini" "$(mcp_ready_agents)" "all three fakes ready"
assert_eq "$HOME/.local/bin/claude" "$(mcp_agent_cli claude)" "claude via ~/.local/bin"
assert_eq "codex" "$(mcp_agent_cli codex)" "codex via PATH"

# ---- per-agent add shapes ----
: >"$FAKE_MCP_LOG"
mcp_agent_add claude "context7|stdio|npx -y @upstash/context7-mcp"
mcp_agent_add codex  "context7|stdio|npx -y @upstash/context7-mcp"
mcp_agent_add gemini "context7|stdio|npx -y @upstash/context7-mcp"
assert_contains "$(mcp_log)" "claude mcp add -s user context7 -- npx -y @upstash/context7-mcp" "claude stdio shape"
assert_contains "$(mcp_log)" "codex mcp add context7 -- npx -y @upstash/context7-mcp" "codex stdio shape"
assert_contains "$(mcp_log)" "gemini mcp add -s user context7 -- npx -y @upstash/context7-mcp" "gemini stdio shape"
mcp_agent_add claude "sentry|http|https://mcp.sentry.dev/mcp"
mcp_agent_add codex  "sentry|http|https://mcp.sentry.dev/mcp"
mcp_agent_add gemini "sentry|http|https://mcp.sentry.dev/mcp"
assert_contains "$(mcp_log)" "claude mcp add -s user --transport http sentry https://mcp.sentry.dev/mcp" "claude http shape"
assert_contains "$(mcp_log)" "codex mcp add sentry --url https://mcp.sentry.dev/mcp" "codex http shape"
assert_contains "$(mcp_log)" "gemini mcp add -s user -t http sentry https://mcp.sentry.dev/mcp" "gemini http shape"
mcp_agent_add gemini "gh|stdio|~/.local/bin/github-mcp.sh"
assert_contains "$(mcp_log)" "gemini mcp add -s user gh -- $HOME/.local/bin/github-mcp.sh" "target expanded when adding"
assert_fail "unknown transport rejected" mcp_agent_add claude "x|sse|y"

# ---- detection ----
assert_ok "claude has (mcp get)" mcp_agent_has claude context7
assert_ok "codex has (mcp get)" mcp_agent_has codex sentry
assert_ok "gemini has (settings.json)" mcp_agent_has gemini sentry
assert_fail "absent" mcp_agent_has codex nosuch
rm -f "$HOME/.gemini/settings.json"
assert_fail "gemini without settings.json -> absent" mcp_agent_has gemini sentry
printf 'not json' >"$HOME/.gemini/settings.json"
assert_fail "gemini unparsable settings.json -> absent" mcp_agent_has gemini sentry

# ---- remove shapes ----
: >"$FAKE_MCP_LOG"
mcp_agent_remove claude context7
mcp_agent_remove codex context7
mcp_agent_remove gemini context7
assert_contains "$(mcp_log)" "claude mcp remove -s user context7" "claude remove shape"
assert_contains "$(mcp_log)" "codex mcp remove context7" "codex remove shape"
assert_contains "$(mcp_log)" "gemini mcp remove -s user context7" "gemini remove shape"
assert_fail "removed" mcp_agent_has claude context7
for a in claude codex gemini; do mcp_agent_remove "$a" sentry; done
mcp_agent_remove gemini gh
out="$(DRY_RUN=1 mcp_agent_add codex "dry|stdio|echo hi")"
assert_contains "$out" "[dry-run] codex mcp add dry -- echo hi" "dry-run add prints"
assert_fail "dry-run add does not add" mcp_agent_has codex dry

finish
```

- [ ] **Step 4: Run to verify failure**

Run: `/bin/bash tests/test_mcp.sh`
Expected: `load_libs` fails to source `lib/mcp.sh` (file missing) and every assertion fails.

- [ ] **Step 5: Create `lib/mcp.sh` (first half)**

```bash
#!/bin/bash
# Managed MCP servers: apply the repo roster dotfiles/mcp-servers.conf to
# every installed agent CLI (Claude Code, Codex, Gemini CLI) through the
# CLI's own `mcp add` / `mcp remove` in user scope, so the servers are there
# in the terminal and in the agents' VS Code extensions alike. Sourced after
# lib/drivers.sh by run.sh, update.sh and the tests. Pure functions; every
# mutation goes through run_cmd; nothing writes to stdout inside a function
# whose output is captured.
#
# Roster record: name|transport|command-or-url [args...]
#   transport  stdio | http
#   a leading ~/ in the target is expanded to $HOME (the CLIs do not)
#
# State ($CONFIG_DIR/mcp.conf): TSV, one "agent<TAB>name<TAB>record" line per
# server this unit applied. A record that changed upstream is re-applied
# (remove + add); a name dropped from the roster is removed. Servers the user
# added themselves are never in the state file and are never touched — a
# roster name that already exists on an agent is left alone, not recorded.

MCP_ROSTER_FILE="${MCP_ROSTER_FILE:-$REPO_ROOT/dotfiles/mcp-servers.conf}"
MCP_KNOWN_AGENTS="claude codex gemini"

# ---- roster ------------------------------------------------------------------

# Prints the records (no comments, no blank lines); rc 1 when the file is missing.
mcp_roster_records() {
  if [ ! -f "$MCP_ROSTER_FILE" ]; then return 1; fi
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$MCP_ROSTER_FILE"
  return 0
}

mcp_record_name()      { printf '%s\n' "$1" | cut -d'|' -f1; }
mcp_record_transport() { printf '%s\n' "$1" | cut -d'|' -f2; }

# The command line (stdio) or URL (http), with a leading ~/ expanded.
mcp_record_target() {
  local t
  t="$(printf '%s\n' "$1" | cut -d'|' -f3-)"
  case "$t" in
    "~/"*) t="$HOME/${t#\~/}" ;;
  esac
  printf '%s\n' "$t"
}

# 0 when name, transport and target are all acceptable.
mcp_record_valid() {
  local name transport target
  name="$(mcp_record_name "$1")"
  transport="$(mcp_record_transport "$1")"
  target="$(mcp_record_target "$1")"
  printf '%s' "$name" | grep -Eq '^[A-Za-z0-9_-]+$' || return 1
  case "$transport" in
    stdio | http) ;;
    *) return 1 ;;
  esac
  [ -n "$target" ]
}

# ---- agents ------------------------------------------------------------------

# Claude Code's native install is ~/.local/bin/claude (apps/claude-code.sh);
# codex and gemini are brew-installed and on PATH.
mcp_agent_cli() {
  case "$1" in
    claude) printf '%s/.local/bin/claude\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

mcp_agent_ready() {
  case "$1" in
    claude) [ -x "$HOME/.local/bin/claude" ] ;;
    codex | gemini) command -v "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

mcp_ready_agents() {
  local a out=""
  for a in $MCP_KNOWN_AGENTS; do
    if mcp_agent_ready "$a"; then out="$out $a"; fi
  done
  printf '%s\n' "${out# }"
}

# mcp_agent_has agent name -> 0 when the agent already has a server by that
# name (any scope). Gemini has no `mcp get`, so its settings file is read.
mcp_agent_has() {
  case "$1" in
    claude | codex) "$(mcp_agent_cli "$1")" mcp get "$2" >/dev/null 2>&1 </dev/null ;;
    gemini)
      if [ ! -f "$HOME/.gemini/settings.json" ]; then return 1; fi
      python3 - "$HOME/.gemini/settings.json" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in (d.get("mcpServers") or {}) else 1)
PY
      ;;
    *) return 1 ;;
  esac
}

# mcp_agent_add agent record — the per-CLI add command in user scope.
mcp_agent_add() {
  local agent="$1" rec="$2" cli name transport target
  cli="$(mcp_agent_cli "$agent")"
  name="$(mcp_record_name "$rec")"
  transport="$(mcp_record_transport "$rec")"
  target="$(mcp_record_target "$rec")"
  # shellcheck disable=SC2086  # a stdio target is a command line: split on purpose
  case "$agent:$transport" in
    claude:stdio) run_cmd "$cli" mcp add -s user "$name" -- $target ;;
    claude:http)  run_cmd "$cli" mcp add -s user --transport http "$name" "$target" ;;
    codex:stdio)  run_cmd "$cli" mcp add "$name" -- $target ;;
    codex:http)   run_cmd "$cli" mcp add "$name" --url "$target" ;;
    gemini:stdio) run_cmd "$cli" mcp add -s user "$name" -- $target ;;
    gemini:http)  run_cmd "$cli" mcp add -s user -t http "$name" "$target" ;;
    *)
      err "mcp: unsupported agent/transport '$agent/$transport' for '$name'"
      return 1
      ;;
  esac
}

mcp_agent_remove() {
  local cli
  cli="$(mcp_agent_cli "$1")"
  case "$1" in
    claude | gemini) run_cmd "$cli" mcp remove -s user "$2" ;;
    codex) run_cmd "$cli" mcp remove "$2" ;;
    *) return 1 ;;
  esac
}
```

- [ ] **Step 6: Run to verify pass**

Run: `/bin/bash tests/test_mcp.sh`
Expected: `0 failed`. Then `tests/run.sh`: every other test file still `0 failed` (the fake `claude`/`codex`/`gemini` on PATH must not disturb `test_context_audit.sh` — read that test; if it relies on a real or own `claude`, make its PATH win, and report it). shellcheck the new fakes by hand: `shellcheck tests/fakes/fake-mcp-cli tests/fakes/claude tests/fakes/codex tests/fakes/gemini`.

- [ ] **Step 7: Commit**

```bash
git add lib/mcp.sh dotfiles/mcp-servers.conf tests/fakes/fake-mcp-cli tests/fakes/claude tests/fakes/codex tests/fakes/gemini tests/lib.sh tests/test_mcp.sh run.sh update.sh
git commit -m "feat(mcp): roster parsing and per-agent mcp add/remove for Claude, Codex, Gemini"
```

---

### Task 5: MCP engine — state file, `mcp_apply`, `mcp_remove_all`

**Files:**
- Modify: `lib/mcp.sh` (append), `tests/test_mcp.sh` (append before `finish`)

**Interfaces:**
- Consumes: everything from Task 4; `in_list`, `log`, `err`, `warn`, `CONFIG_DIR`, `DRY_RUN` from `lib/common.sh`.
- Produces: `mcp_state_file`, `mcp_state_get A NAME` (prints record, rc 1 when absent), `mcp_state_names A`, `mcp_state_put A NAME RECORD`, `mcp_state_delete A NAME`, `mcp_apply` (rc 1 if anything failed), `mcp_remove_all`.

- [ ] **Step 1: Append the failing tests**

Insert before `finish` in `tests/test_mcp.sh`:

```bash
# ---- state ----
mcp_state_put codex context7 "context7|stdio|x"
assert_eq "context7|stdio|x" "$(mcp_state_get codex context7)" "state put/get"
assert_fail "state absent" mcp_state_get claude context7
mcp_state_put codex github "github|stdio|y"
assert_eq "context7 github" "$(mcp_state_names codex | tr '\n' ' ' | sed 's/ $//')" "state names per agent"
mcp_state_delete codex context7
assert_fail "state deleted" mcp_state_get codex context7
assert_eq "1" "$(state | wc -l | tr -d ' ')" "one line left"
mcp_state_delete codex github
assert_eq "0" "$(state | wc -l | tr -d ' ')" "state empty"

# ---- apply: first run adds everything and records it ----
printf 'context7|stdio|npx -y @upstash/context7-mcp\ngithub|stdio|~/.local/bin/github-mcp.sh\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
assert_ok "first apply" mcp_apply
assert_eq "6" "$(grep -c ' mcp add ' "$FAKE_MCP_LOG")" "2 servers x 3 agents added"
assert_eq "6" "$(state | wc -l | tr -d ' ')" "6 state lines"
assert_eq "github|stdio|~/.local/bin/github-mcp.sh" "$(mcp_state_get codex github)" "state stores the raw record"
assert_ok "gemini really has it" mcp_agent_has gemini github

# second run: nothing to do
: >"$FAKE_MCP_LOG"
assert_ok "second apply" mcp_apply
assert_not_contains "$(mcp_log)" " mcp add " "second apply adds nothing"
assert_not_contains "$(mcp_log)" " mcp remove " "second apply removes nothing"

# changed record -> remove then add, on every agent
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\ngithub|stdio|~/.local/bin/github-mcp.sh\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_contains "$(mcp_log)" "claude mcp remove -s user context7" "changed: removed"
assert_contains "$(mcp_log)" "claude mcp add -s user context7 -- npx -y @upstash/context7-mcp@latest" "changed: re-added"
assert_eq "3" "$(grep -c ' mcp remove ' "$FAKE_MCP_LOG")" "changed: one remove per agent"
assert_not_contains "$(mcp_log)" "github-mcp.sh" "unchanged record untouched"
assert_eq "context7|stdio|npx -y @upstash/context7-mcp@latest" "$(mcp_state_get gemini context7)" "state updated"

# dropped from the roster -> removed everywhere, state cleared
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_eq "3" "$(grep -c ' mcp remove .*github' "$FAKE_MCP_LOG")" "dropped: removed from 3 agents"
assert_fail "dropped: state gone" mcp_state_get codex github
assert_fail "dropped: really gone" mcp_agent_has codex github

# a server the user added with a roster name is left alone and never recorded
printf 'mine\n' >>"$FAKE_MCP_DIR/codex"
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nmine|stdio|echo hi\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_not_contains "$(mcp_log)" "codex mcp add mine" "pre-existing user server not re-added"
assert_fail "user server not recorded" mcp_state_get codex mine
assert_contains "$(mcp_log)" "claude mcp add -s user mine -- echo hi" "other agents still get it"
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_contains "$(mcp_log)" "claude mcp remove -s user mine" "managed copy removed"
assert_not_contains "$(mcp_log)" "codex mcp remove mine" "user server not removed"
assert_ok "user server survives" grep -qx mine "$FAKE_MCP_DIR/codex"

# a server the user removed by hand is simply re-added
grep -vx context7 "$FAKE_MCP_DIR/codex" >"$FAKE_MCP_DIR/codex.tmp"; mv "$FAKE_MCP_DIR/codex.tmp" "$FAKE_MCP_DIR/codex"
: >"$FAKE_MCP_LOG"
mcp_apply
assert_contains "$(mcp_log)" "codex mcp add context7 -- npx -y @upstash/context7-mcp@latest" "hand-removed server re-added"

# not-ready agent skipped with a message, no calls
mcp_agent_ready() { [ "$1" != gemini ]; }
: >"$FAKE_MCP_LOG"
out="$(mcp_apply 2>&1)"
assert_contains "$out" "mcp: gemini not installed — skipped" "skip message"
assert_not_contains "$(mcp_log)" "gemini " "no gemini calls when not ready"
. "$REPO_ROOT/lib/mcp.sh"

# malformed record: reported, others still applied, rc 1
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nbad name|stdio|x\nok|stdio|echo ok\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
out="$(mcp_apply 2>&1)"; rc=$?
assert_eq "1" "$rc" "malformed record -> rc 1"
assert_contains "$out" "malformed roster record: bad name|stdio|x" "malformed reported"
assert_contains "$(mcp_log)" "codex mcp add ok -- echo ok" "later records still applied"
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\n' >"$MCP_ROSTER_FILE"
mcp_apply

# failed add: reported, pass continues, rc 1, not recorded; retry works
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nnew|stdio|echo new\n' >"$MCP_ROSTER_FILE"
export FAKE_MCP_FAIL=1
assert_fail "failed add returns 1" mcp_apply
assert_fail "failed add not recorded" mcp_state_get claude new
unset FAKE_MCP_FAIL
assert_ok "retry succeeds" mcp_apply
assert_ok "recorded after retry" mcp_state_get claude new

# missing roster: rc 1, nothing touched
MCP_ROSTER_FILE="$SANDBOX/missing.conf"
: >"$FAKE_MCP_LOG"
assert_fail "missing roster -> rc 1" mcp_apply
assert_eq "" "$(mcp_log)" "missing roster -> no calls"
MCP_ROSTER_FILE="$SANDBOX/roster.conf"

# dry-run: prints, mutates nothing
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nnew|stdio|echo new\ndry|stdio|echo dry\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
out="$(DRY_RUN=1 mcp_apply)"
assert_contains "$out" "[dry-run] $HOME/.local/bin/claude mcp add -s user dry -- echo dry" "dry-run echoes add"
assert_not_contains "$(mcp_log)" " mcp add " "dry-run calls no add"
assert_fail "dry-run writes no state" mcp_state_get claude dry

# remove_all: every managed server gone, state file gone, user server kept
printf 'context7|stdio|npx -y @upstash/context7-mcp@latest\nnew|stdio|echo new\n' >"$MCP_ROSTER_FILE"
: >"$FAKE_MCP_LOG"
assert_ok "remove all" mcp_remove_all
assert_eq "6" "$(grep -c ' mcp remove ' "$FAKE_MCP_LOG")" "every managed server removed"
assert_fail "state file gone" test -f "$(mcp_state_file)"
assert_ok "user server still there" grep -qx mine "$FAKE_MCP_DIR/codex"
assert_fail "managed server really gone" mcp_agent_has gemini context7
```

- [ ] **Step 2: Run to verify failure**

Run: `/bin/bash tests/test_mcp.sh`
Expected: FAIL from "state put/get" onward (`mcp_state_put: command not found`).

- [ ] **Step 3: Append the second half of `lib/mcp.sh`**

```bash
# ---- state: $CONFIG_DIR/mcp.conf --------------------------------------------
# TSV: agent<TAB>name<TAB>record. Names never contain tabs (validated), so a
# record round-trips byte for byte. Not written under --dry-run.

mcp_state_file() { printf '%s/mcp.conf\n' "$CONFIG_DIR"; }

# Prints the record applied for agent+name; rc 1 when absent.
mcp_state_get() {
  local f
  f="$(mcp_state_file)"
  if [ ! -f "$f" ]; then return 1; fi
  awk -F'\t' -v a="$1" -v n="$2" '$1 == a && $2 == n { print $3; found = 1 } END { exit found ? 0 : 1 }' "$f"
}

# Names applied for an agent, one per line.
mcp_state_names() {
  local f
  f="$(mcp_state_file)"
  if [ ! -f "$f" ]; then return 0; fi
  awk -F'\t' -v a="$1" '$1 == a { print $2 }' "$f"
}

mcp_state_write() { # agent name record put|delete
  local f tmp
  f="$(mcp_state_file)"
  mkdir -p "$CONFIG_DIR"
  tmp="$f.tmp.$$"
  {
    printf '# Managed by run.sh — MCP servers applied per agent (agent, name, roster record).\n'
    if [ -f "$f" ]; then
      grep -v '^#' "$f" | awk -F'\t' -v a="$1" -v n="$2" '!($1 == a && $2 == n)'
    fi
    if [ "$4" = put ]; then printf '%s\t%s\t%s\n' "$1" "$2" "$3"; fi
  } >"$tmp"
  mv "$tmp" "$f"
}

mcp_state_put() { # agent name record
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  mcp_state_write "$1" "$2" "$3" put
}

mcp_state_delete() { # agent name
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  if [ -f "$(mcp_state_file)" ]; then mcp_state_write "$1" "$2" "" delete; fi
}

# ---- apply -------------------------------------------------------------------

# Bring one agent in line with the roster. Continues past failures; rc 1 if
# any. State is written only for operations that succeeded, so the next run
# retries exactly what failed.
mcp_apply_agent() {
  local agent="$1" rc=0 rec name state n i
  # Line-numbered iteration (not `while read`) so the CLI calls inside never
  # compete with the loop for stdin — same rule as lib/skills.sh.
  n="$(mcp_roster_records | grep -c .)"
  i=1
  while [ "$i" -le "$n" ]; do
    rec="$(mcp_roster_records | sed -n "${i}p")"
    i=$((i + 1))
    if [ -z "$rec" ]; then continue; fi
    if ! mcp_record_valid "$rec"; then
      err "mcp: malformed roster record: $rec"
      rc=1
      continue
    fi
    name="$(mcp_record_name "$rec")"
    state="$(mcp_state_get "$agent" "$name" || true)"
    if mcp_agent_has "$agent" "$name"; then
      if [ "$state" = "$rec" ]; then continue; fi
      if [ -z "$state" ]; then
        log "mcp: $agent already has '$name' (not added by this unit) — leaving it alone"
        continue
      fi
      log "mcp: $agent: '$name' changed in the roster — re-adding"
      if ! mcp_agent_remove "$agent" "$name"; then
        err "mcp: $agent: could not remove '$name'"
        rc=1
        continue
      fi
    else
      log "mcp: $agent: adding '$name'"
    fi
    if mcp_agent_add "$agent" "$rec"; then
      mcp_state_put "$agent" "$name" "$rec"
    else
      err "mcp: $agent: could not add '$name'"
      rc=1
    fi
  done
  # Names this unit applied earlier that the roster no longer lists.
  for name in $(mcp_state_names "$agent"); do
    if mcp_roster_records | grep -q "^$name|"; then continue; fi
    log "mcp: $agent: '$name' dropped from the roster — removing"
    if ! mcp_agent_has "$agent" "$name" || mcp_agent_remove "$agent" "$name"; then
      mcp_state_delete "$agent" "$name"
    else
      err "mcp: $agent: could not remove '$name'"
      rc=1
    fi
  done
  return "$rc"
}

# Apply the roster to every installed agent; agents not installed yet are
# skipped and picked up on a later update (same rule as the skills units).
mcp_apply() {
  local rc=0 a agents
  if ! mcp_roster_records >/dev/null; then
    err "mcp: roster $MCP_ROSTER_FILE missing"
    return 1
  fi
  agents="$(mcp_ready_agents)"
  for a in $MCP_KNOWN_AGENTS; do
    if ! in_list "$a" "$agents"; then
      log "mcp: $a not installed — skipped (applied on a later update once the agent exists)"
      continue
    fi
    mcp_apply_agent "$a" || rc=1
  done
  return "$rc"
}

# Remove every server this unit applied, from every agent, and drop the state
# file. Servers not in the state file are never touched.
mcp_remove_all() {
  local rc=0 a name
  for a in $MCP_KNOWN_AGENTS; do
    for name in $(mcp_state_names "$a"); do
      if ! mcp_agent_ready "$a"; then
        warn "mcp: $a not installed — cannot remove '$name'; dropping it from the state"
        mcp_state_delete "$a" "$name"
        continue
      fi
      if ! mcp_agent_has "$a" "$name" || mcp_agent_remove "$a" "$name"; then
        mcp_state_delete "$a" "$name"
      else
        err "mcp: $a: could not remove '$name'"
        rc=1
      fi
    done
  done
  if [ "$rc" = 0 ] && [ "$DRY_RUN" != 1 ] && [ -f "$(mcp_state_file)" ]; then
    rm -f "$(mcp_state_file)"
  fi
  return "$rc"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `/bin/bash tests/test_mcp.sh`
Expected: `0 failed`. Then `tests/run.sh` — every file `0 failed`, shellcheck clean.

- [ ] **Step 5: Commit**

```bash
git add lib/mcp.sh tests/test_mcp.sh
git commit -m "feat(mcp): apply the roster with a per-machine state file and remove-all"
```

---

### Task 6: `mcp-servers` unit, GitHub launcher, install.sh

**Files:**
- Create: `apps/mcp-servers.sh`, `bin/github-mcp.sh`, `tests/test_github_mcp.sh`
- Modify: `install.sh` (after the `claude-context-audit.sh` link line), `tests/run.sh` (shellcheck list)

**Interfaces:**
- Consumes: `mcp_apply`, `mcp_remove_all` (Task 5); `formula_install/_update/_uninstall/_installed` (`lib/drivers.sh`).
- Produces: unit functions `mcp_servers_install/_update/_uninstall/_installed`; `~/.local/bin/github-mcp.sh`.

- [ ] **Step 1: Write the failing launcher test**

`tests/test_github_mcp.sh`:

```bash
#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
# The launcher runs from an agent's environment: give it a fake gh and a
# fake server on PATH and check what it execs.
mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/gh" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "auth token" ]; then printf '%s\n' "${FAKE_GH_TOKEN-tok123}"; exit "${FAKE_GH_RC:-0}"; fi
exit 2
EOF
cat >"$SANDBOX/bin/github-mcp-server" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$GITHUB_PERSONAL_ACCESS_TOKEN" "$*"
EOF
chmod +x "$SANDBOX/bin/gh" "$SANDBOX/bin/github-mcp-server"
export PATH="$SANDBOX/bin:$PATH"
w="$REPO_ROOT/bin/github-mcp.sh"

assert_ok "launcher is executable" test -x "$w"
assert_eq "tok123 stdio --toolsets repos,issues,pull_requests" "$("$w")" "token via env; stdio with limited toolsets"
out="$(FAKE_GH_RC=1 "$w" 2>&1)"; rc=$?
assert_eq "1" "$rc" "gh not logged in -> rc 1"
assert_contains "$out" "gh auth login" "gh not logged in -> hint"
out="$(FAKE_GH_TOKEN= "$w" 2>&1)"; rc=$?
assert_eq "1" "$rc" "empty token -> rc 1"
assert_contains "$out" "gh auth login" "empty token -> hint"
finish
```

(The "binary missing" branches are deliberately untested: the launcher falls back to `/opt/homebrew/bin`, where the real `gh` and `github-mcp-server` live on the primary machine, so such a test would pass or fail depending on the host.)

- [ ] **Step 2: Run to verify failure**

Run: `/bin/bash tests/test_github_mcp.sh`
Expected: FAIL "launcher is executable" and following.

- [ ] **Step 3: Create the launcher**

`bin/github-mcp.sh`:

```bash
#!/bin/bash
# GitHub MCP server launcher for the managed MCP roster
# (dotfiles/mcp-servers.conf). Runs github-mcp-server (brew formula, installed
# by the mcp-servers unit) over stdio with the token gh is logged in with, so
# no token is stored in any agent's config file. Claude Code, Codex and Gemini
# CLI launch this — sometimes from a GUI app whose PATH lacks Homebrew, hence
# the explicit lookup. Toolsets are limited to keep every agent's tool list
# (and Claude Code's per-turn payload) small; widen the list here if needed.
set -u

find_bin() {
  local b
  for b in "$(command -v "$1" 2>/dev/null)" "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
    if [ -n "$b" ] && [ -x "$b" ]; then
      printf '%s\n' "$b"
      return 0
    fi
  done
  return 1
}

if ! gh="$(find_bin gh)"; then
  echo "github-mcp: gh not found — select the gh unit in run.sh" >&2
  exit 1
fi
if ! server="$(find_bin github-mcp-server)"; then
  echo "github-mcp: github-mcp-server not found — select the mcp-servers unit in run.sh" >&2
  exit 1
fi
if ! token="$("$gh" auth token 2>/dev/null)" || [ -z "$token" ]; then
  echo "github-mcp: gh is not logged in — run: gh auth login" >&2
  exit 1
fi
GITHUB_PERSONAL_ACCESS_TOKEN="$token" exec "$server" stdio --toolsets repos,issues,pull_requests
```

`chmod +x bin/github-mcp.sh`.

In `install.sh`, after the `claude-context-audit.sh` link line add:

```bash
link "$REPO/bin/github-mcp.sh" "$HOME/.local/bin/github-mcp.sh"
```

In `tests/run.sh`, change the shellcheck line to:

```bash
  shellcheck lib/*.sh apps/*.sh run.sh update.sh install.sh bin/github-mcp.sh tests/lib.sh tests/run.sh tests/fakes/npx tests/fakes/code tests/fakes/fake-mcp-cli tests/fakes/claude tests/fakes/codex tests/fakes/gemini $tests || rc=1
```

- [ ] **Step 4: Create the unit**

`apps/mcp-servers.sh`:

```bash
#!/bin/bash
# shellcheck disable=SC2034
# Managed MCP servers — the roster dotfiles/mcp-servers.conf applied to every
# installed agent CLI (Claude Code, Codex, Gemini CLI) in user scope through
# the CLI's own `mcp add`, so the servers are available in the terminal and in
# the agents' VS Code extensions alike. Engine in lib/mcp.sh; this file is the
# unit plus the github-mcp-server formula the roster's github entry needs.
# The id sorts after claude-code, codex and gemini-cli (apps/*.sh load
# alphabetically), so a fresh machine gets its servers on the first run.
APP_NAME="MCP servers (context7, GitHub)"
APP_CATEGORY="AI"
APP_NOTE="Servers are added per agent in user scope; agents not installed yet are picked up on the next update. The github server takes its token from 'gh auth token' — run 'gh auth login' once. MCP tools add to Claude Code's per-turn payload: run claude-context-audit.sh after roster changes."

mcp_servers_install()   { formula_install github-mcp-server && mcp_apply; }
mcp_servers_update()    { formula_update github-mcp-server && mcp_apply; }
# keep and zap are the same: the servers are removed from every agent's
# config either way; nothing else is written.
mcp_servers_uninstall() { mcp_remove_all && formula_uninstall github-mcp-server; }
mcp_servers_installed() { formula_installed github-mcp-server; }
```

- [ ] **Step 5: Run the whole suite**

Run: `tests/run.sh`
Expected: shellcheck clean (all new files now exist), every test file `0 failed`, including the `mcp-servers` assertions in `tests/test_units.sh`.

- [ ] **Step 6: Dry-run the real entry points**

Run: `./run.sh --dry-run --non-interactive --apps vscode,mcp-servers,gemini-cli 2>&1 | grep -v 'removing\|uninstall\|not installed via brew'`
Expected: prints the cask install, `[dry-run] install agent extensions once VS Code is present`, the `github-mcp-server` install, and `[dry-run] ... mcp add ...` lines for the agents present on this machine (claude, codex, gemini). No `error:` lines. (`--non-interactive` stops the keep-or-zap prompts for the apps this ad-hoc selection leaves out; under `--dry-run` nothing is removed and the selection is not saved.)

- [ ] **Step 7: Commit**

```bash
git add apps/mcp-servers.sh bin/github-mcp.sh install.sh tests/run.sh tests/test_github_mcp.sh
git commit -m "feat(apps): mcp-servers unit with a gh-backed GitHub MCP launcher"
```

---

### Task 7: Docs and spec status

**Files:**
- Modify: `README.md` (managed-files table after line 48; apps table after the `agent-skill-suites` row and after line 91; the paragraph starting line 107; the context-audit bullet around line 169)
- Modify: `docs/howto.md` (table of contents; `agent-skills / agent-skill-suites` section first bullet; two new sections)
- Modify: `docs/superpowers/specs/2026-09-10-vscode-agents-mcp-design.md` (status line)

- [ ] **Step 1: README managed-files table**

After the `bin/claude-context-audit.sh` row add:

```markdown
| `bin/github-mcp.sh` | `~/.local/bin/github-mcp.sh` (symlink) | Launcher for the GitHub MCP server in the `mcp-servers` roster: takes the token from `gh auth token` at start, so no token lives in any agent's config; limits the toolsets to repos, issues and pull requests (edit the script to widen) |
| `dotfiles/mcp-servers.conf` | read in place by the `mcp-servers` unit | Managed MCP roster, one server per line (`name|transport|command-or-url`), applied to Claude Code, Codex and Gemini CLI in user scope through each CLI's own `mcp add`; see [MCP servers](docs/howto.md#mcp-servers) |
```

- [ ] **Step 2: README apps table**

After the `agent-skill-suites` row add:

```markdown
| `mcp-servers` | MCP servers (context7, GitHub) | roster `dotfiles/mcp-servers.conf` applied through `claude mcp add -s user`, `codex mcp add`, `gemini mcp add -s user`; brew formula `github-mcp-server`; needs `gh auth login` for the github entry; state in `~/.mac-bootstrap/mcp.conf`; deselect removes only the servers it added |
```

After the `sublime-text` row add:

```markdown
| `vscode` | Visual Studio Code | brew cask `visual-studio-code` (self-updates); also installs the agent extensions for whichever of `claude-code` (anthropic.claude-code), `codex` (openai.chatgpt), `gemini-cli` (Gemini CLI Companion + Gemini Code Assist) is installed — they run the same CLIs against the same `~/.claude`, `~/.codex`, `~/.gemini`, so skills and MCP servers carry over; zap removes extensions and user settings |
```

- [ ] **Step 3: README prose**

In the paragraph beginning "The agent-tooling units", change the sentence "reconciles the shared store `~/.agents/skills` against it" to read "reconciles the shared store `~/.agents/skills` against it, linking into `~/.claude/skills`, `~/.codex/skills` and `~/.gemini/skills` for whichever agents are installed".

In the "Claude Code context audit" section, after the sentence ending "(21 → 13 tools, input tokens −15%)." add: "The `mcp-servers` roster adds tools the same way (the GitHub server is limited to three toolsets for that reason) — run the audit after changing it."

- [ ] **Step 4: howto**

Table of contents: add `- [vscode](#vscode)` after the `android-studio` entry and `- [mcp-servers](#mcp-servers)` after the `gsd` entry.

In `## agent-skills / agent-skill-suites`, first bullet: change "(`~/.claude/skills`, `~/.codex/skills`)" to "(`~/.claude/skills`, `~/.codex/skills`, `~/.gemini/skills` — Gemini CLI reads it natively, `gemini skills list` shows what it sees)".

Add after the `## gsd` section:

```markdown
## mcp-servers

- **What it does.** Applies `dotfiles/mcp-servers.conf` to every installed
  agent CLI in user scope: `claude mcp add -s user`, `codex mcp add`,
  `gemini mcp add -s user`. Agents not installed yet are skipped and picked
  up on the next `./update.sh`. What was applied is recorded per machine in
  `~/.mac-bootstrap/mcp.conf`; only servers in that file are ever removed, so
  anything you add yourself with the CLIs is left alone.
- **Adding a server.** One line, `name|stdio|command args...` or
  `name|http|url`; a leading `~/` is expanded. Commit, then `./update.sh`.
  Editing a line re-applies it (remove + add); deleting a line removes the
  server from every agent. Verify with `claude mcp list`, `codex mcp list`,
  `gemini mcp list`.
- **github.** `bin/github-mcp.sh` (linked into `~/.local/bin`) runs the
  `github-mcp-server` formula with the token from `gh auth token`; run
  `gh auth login` once. Toolsets are limited to `repos,issues,pull_requests`
  — edit the `--toolsets` list in the script to widen.
- **Context cost.** Every server's tools ride along in Claude Code's per-turn
  payload. Run `claude-context-audit.sh` after a roster change; trim
  individual tools with bare `mcp__<server>__<tool>` names in
  `permissions.deny` in `dotfiles/.claude/settings.json`.
- **Name clash.** If an agent already has a server with a roster name that
  this unit did not add, the unit logs it and leaves it alone.

## vscode

- **Agent extensions.** Installed by the unit for whichever agent CLIs are
  installed: `claude-code` → anthropic.claude-code, `codex` → openai.chatgpt,
  `gemini-cli` → Gemini CLI Companion and Gemini Code Assist. Each extension
  signs in on first use (Anthropic, ChatGPT and Google accounts
  respectively). Skills and MCP servers need nothing extra — the extensions
  run the same CLIs against the same home directories.
- **Ordering.** On a first run that also installs the agent CLIs, `vscode`
  is applied last (units load alphabetically), so the extensions land on the
  same run. If an agent is added later, its extension follows on the next
  `./run.sh` / `./update.sh`.
- **Removal.** Deselecting an agent CLI leaves its extension in VS Code
  (uninstall it from the Extensions view). Deselecting `vscode` with zap
  removes `~/.vscode` and the app's user settings along with the app.
```

- [ ] **Step 5: Spec status**

Change the spec's status line to:

```markdown
**Status: implemented 2026-09-10** — plan in `docs/superpowers/plans/2026-09-10-vscode-agents-mcp.md`, engine in `lib/mcp.sh`, VS Code driver in `lib/drivers.sh`, tests in `tests/`.
```

- [ ] **Step 6: Final verification**

Run: `tests/run.sh`
Expected: shellcheck clean, all test files `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/howto.md docs/superpowers/specs/2026-09-10-vscode-agents-mcp-design.md
git commit -m "docs: document the vscode and mcp-servers units and the Gemini skills target"
```

---

## Post-merge manual check (primary machine)

Not part of the tasks — run once after the plan lands, and record the result in the commit or an issue:

```bash
./run.sh --apps <current selection>,vscode,mcp-servers
claude mcp list; codex mcp list; gemini mcp list
gemini skills list
code --list-extensions
claude-context-audit.sh
```

Expected: context7 and github listed by all three CLIs, Gemini lists the shared skills, four extensions present, and the audit shows the tool-count delta from the two new servers.
