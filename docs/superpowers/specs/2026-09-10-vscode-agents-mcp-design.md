# VS Code, Gemini Skills and Managed MCP Servers — Design

**Status: implemented 2026-09-10** — plan in `docs/superpowers/plans/2026-09-10-vscode-agents-mcp.md`, engine in `lib/mcp.sh`, VS Code driver in `lib/drivers.sh`, tests in `tests/`.

## Goal

Make the three managed coding agents — Claude Code, Codex CLI and Gemini CLI —
work inside Visual Studio Code with the same skills and MCP servers they have
in the terminal, and manage all of it from this repo:

- Add **VS Code** as a managed app (`vscode` unit) that also installs each
  agent's VS Code extension whenever that agent's CLI is installed.
- Teach the skills engine about **Gemini CLI** so every `*` roster entry links
  into `~/.gemini/skills` the way it already does for Claude and Codex.
- Add a **managed MCP roster** (`mcp-servers` unit) applied to all three
  agents' user-scope configuration through each CLI's own `mcp add`, starting
  with context7 and GitHub.

## Background

Verified 2026-09-10 on the primary machine:

- VS Code is not installed. Homebrew cask `visual-studio-code` (1.137.0,
  `auto_updates`) ships a `code` CLI shim; the app also keeps a copy at
  `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`.
- Marketplace extension IDs, checked against the gallery API:
  `anthropic.claude-code` (Claude Code for VS Code), `openai.chatgpt` (Codex —
  OpenAI's coding agent), `google.gemini-cli-vscode-ide-companion` (Gemini
  CLI Companion), `google.geminicodeassist` (Gemini Code Assist).
- All three extensions drive the same CLI against the same home directory
  (`~/.claude`, `~/.codex`, `~/.gemini`). Skills and MCP servers configured
  for the CLI are therefore available in VS Code with no extra wiring; the
  work is to make sure each agent *has* them.
- Skills: `lib/skills.sh` knows only `claude-code` and `codex`
  (`SKILLS_KNOWN_AGENTS`). Gemini CLI 0.46 is installed but has never run, so
  `~/.gemini` does not exist and nothing is linked for it. The skills.sh CLI
  supports the agent key `gemini-cli` with directory `~/.gemini/skills`;
  Gemini CLI has native skill support (`gemini skills list`).
- MCP: no agent has a repo-managed server. Claude's two servers come from
  plugins (context-mode, cloudflare); Codex has only the ChatGPT app's bundled
  ones; Gemini has none. CLI interfaces:

  | Agent | Add (stdio) | Add (http) | Exists? | Remove | Config file |
  |---|---|---|---|---|---|
  | claude | `claude mcp add -s user NAME -- CMD ARGS` | `claude mcp add -s user --transport http NAME URL` | `claude mcp get NAME` (rc 1 if missing) | `claude mcp remove -s user NAME` | `~/.claude.json` |
  | codex | `codex mcp add NAME -- CMD ARGS` | `codex mcp add NAME --url URL` | `codex mcp get NAME` (rc 1 if missing) | `codex mcp remove NAME` | `~/.codex/config.toml` |
  | gemini | `gemini mcp add -s user NAME CMD ARGS` | `gemini mcp add -s user -t http NAME URL` | no `get`; read `mcpServers` in the JSON | `gemini mcp remove -s user NAME` | `~/.gemini/settings.json` |

- The GitHub MCP server is available as brew formula `github-mcp-server`
  (1.12.1). It reads `GITHUB_PERSONAL_ACCESS_TOKEN` and accepts `--toolsets`
  to limit the tools it exposes. The full server exposes 40+ tools, each of
  which lands in Claude's per-turn payload (see the README's context audit).
- `discover_apps` sources `apps/*.sh` in glob (alphabetical) order and
  `run.sh` installs in that order. A unit that depends on other units being
  installed first is served by a name that sorts after them.

## Decisions

1. **One `vscode` unit owns extension installs.** The unit installs the
   extensions for whichever agent CLIs are installed at run time and re-checks
   on every update. Alternatives rejected: per-agent units installing their
   own extension (splits VS Code knowledge across four files, and ordering
   would leave the first run incomplete); one selectable unit per extension
   (three more checklist rows for a decision that follows from the agent
   selection anyway). Deselecting an agent CLI does not uninstall its
   extension — that is VS Code's own job and losing an extension's settings
   for an app that is still installed would surprise.
2. **Gemini gets both extensions.** The Companion gives the `gemini` CLI in
   the integrated terminal IDE context; Code Assist adds the chat panel with
   agent mode, which also runs on Gemini CLI. User choice 2026-09-10.
3. **Gemini joins the skills engine as `gemini-cli`.** No new selection
   prompts: the rosters already say `*` for agents, so the reconcile pass
   simply gains a third `-a` target. The gemini-cli unit creates
   `~/.gemini/skills` on install so the agent counts as ready on the same
   run. obra/superpowers stays Codex-only (it is a Claude Code plugin there).
4. **MCP servers are a repo roster applied through each CLI.** Editing
   `~/.claude.json`, `config.toml` and `settings.json` by hand would fight
   three different writers; each CLI's `mcp add` is the supported path and
   handles its own file format. The roster is data in `dotfiles/`, the engine
   is `lib/mcp.sh`, the unit is `apps/mcp-servers.sh` — same split as the
   skills units.
5. **Unit id `mcp-servers`, not `agent-mcp`.** It sorts after `claude-code`,
   `codex` and `gemini-cli` and before `vscode`, so on a fresh machine the
   roster applies on the first run. `agent-mcp` would sort first and defer
   to the next `update.sh`.
6. **GitHub via a wrapper, token from `gh`.** `bin/github-mcp.sh` reads the
   token with `gh auth token` at launch and execs `github-mcp-server stdio`.
   No token is stored in any of the three config files, and the repo's
   existing `gh auth login` step is the only credential setup. Toolsets are
   limited to `repos,issues,pull_requests` to bound the context cost; edit
   the wrapper to widen it. User choice 2026-09-10.
7. **Initial roster: context7 and github.** User choice 2026-09-10. playwright
   was offered and not selected.

## Architecture

### `vscode` unit — `apps/vscode.sh`

```
APP_NAME="Visual Studio Code"; APP_CATEGORY="Development"
vscode_install    cask_install visual-studio-code; vscode_extensions_apply
vscode_update     cask_update  visual-studio-code; vscode_extensions_apply
vscode_uninstall  cask_uninstall visual-studio-code "$1"
vscode_installed  cask_installed visual-studio-code
```

`VSCODE_AGENT_EXTENSIONS` is the mapping, one record per line,
`agent-unit-id|ext.id ext.id`:

```
claude-code|anthropic.claude-code
codex|openai.chatgpt
gemini-cli|google.gemini-cli-vscode-ide-companion google.geminicodeassist
```

`vscode_extensions_apply` walks the mapping; for each agent whose unit
reports installed (`<unit>_installed`, discovered functions are in scope), it
installs every listed extension that `vscode_ext_installed` does not report.
Agents not installed are skipped silently. Extensions update themselves
inside VS Code, so update only fills gaps. Keep-mode uninstall removes the
app; zap uses the cask's zap, which also removes `~/.vscode` (extensions)
and the app's Application Support (user settings). `APP_NOTE` says so.

### VS Code driver — `lib/drivers.sh`

```
vscode_code_bin        prints the `code` CLI: `command -v code`, else the
                       app-bundle path; rc 1 when neither exists
vscode_ext_installed   id -> 0 when `code --list-extensions` lists it
                       (case-insensitive: the CLI lowercases publisher ids)
vscode_ext_install     id -> run_cmd code --install-extension id
```

`--list-extensions` is read once per apply pass (cached in a variable), not
once per extension.

### Gemini in the skills engine — `lib/skills.sh`, `apps/gemini-cli.sh`

- `skills_agent_dir`: `gemini-cli) ~/.gemini/skills`.
- `skills_agent_home`: `gemini-cli) ~/.gemini`.
- `SKILLS_KNOWN_AGENTS="claude-code codex gemini-cli"`.
- `gemini_cli_install` runs `mkdir -p ~/.gemini/skills` after the formula
  install (through `run_cmd`); `gemini_cli_uninstall` in zap mode removes
  `~/.gemini`. Keep mode leaves it. No attempt is made to unlink skills when
  the agent goes away: symlinks in a directory nobody reads are harmless, and
  a later `skills remove` for a name cleans them everywhere.
- Roster comments in both skills units and the README sentence listing agent
  dirs gain Gemini.

### MCP roster — `dotfiles/mcp-servers.conf`

One record per line, `#` comments and blank lines ignored:

```
# name|transport|command-or-url [args...]
context7|stdio|npx -y @upstash/context7-mcp
github|stdio|~/.local/bin/github-mcp.sh
```

`transport` is `stdio` or `http`. A leading `~/` in the command is expanded
to `$HOME` at apply time (the CLIs do not expand it). Names must match
`[A-Za-z0-9_-]+`. No env-var or header fields in rev 1; add columns when a
server needs them.

### MCP engine — `lib/mcp.sh`

Sourced after `lib/drivers.sh`. Same style as `lib/skills.sh`: pure
functions, every mutation through `run_cmd`, no `log` on stdout inside
captured functions.

```
MCP_ROSTER_FILE      $REPO_ROOT/dotfiles/mcp-servers.conf
MCP_KNOWN_AGENTS     "claude codex gemini"
mcp_agent_ready a    claude: -x ~/.local/bin/claude; codex: command -v codex;
                     gemini: command -v gemini
mcp_roster_records   prints the non-comment lines
mcp_agent_has a n    claude/codex: `<cli> mcp get n` rc; gemini: python3
                     reads ~/.gemini/settings.json .mcpServers[n]
mcp_agent_add a rec  builds the per-agent add command from the record
mcp_agent_remove a n per-agent remove command
mcp_state_file       $CONFIG_DIR/mcp.conf
mcp_state_get a n    the record last applied for agent a, name n (or none)
mcp_state_put/delete
mcp_apply            for each ready agent: for each roster record — if
                     state == record and agent has it: skip; if state != record
                     and agent has it: remove, add; if missing: add; then
                     state put. Afterwards every state entry for that agent
                     whose name is no longer in the roster: remove, state delete.
mcp_remove_all       for each ready agent: remove every state entry; delete state
```

The state file is shell-sourced like `skills.conf`, one line per agent+name
(`MCP_claude__context7="context7|stdio|npx -y @upstash/context7-mcp"`), so a
record change is detected by string comparison and a machine whose roster
came from an older checkout is corrected on the next run. Servers the user
adds themselves are never touched: only names present in the state file are
ever removed.

Agents not ready are skipped with the same one-line log the skills units use
(`installed on a later update once the agent exists`).

### `mcp-servers` unit — `apps/mcp-servers.sh`

```
APP_NAME="MCP servers (context7, GitHub)"; APP_CATEGORY="AI"
mcp_servers_install    formula_install github-mcp-server; mcp_apply
mcp_servers_update     formula_update  github-mcp-server; mcp_apply
mcp_servers_uninstall  mcp_remove_all; formula_uninstall github-mcp-server
mcp_servers_installed  formula_installed github-mcp-server
```

Keep and zap are identical (nothing else to zap). `APP_NOTE` reminds that
the github server needs `gh auth login` and that adding MCP tools grows
Claude's per-turn payload — run `claude-context-audit.sh` after changes and
trim with `permissions.deny` in `dotfiles/.claude/settings.json` if needed.

### GitHub wrapper — `bin/github-mcp.sh`

Installed by `install.sh` as a symlink at `~/.local/bin/github-mcp.sh`, same
as the other managed scripts. Runs as `/bin/bash` from a GUI-launched agent
whose PATH may lack Homebrew, so it resolves `gh` and `github-mcp-server`
itself: `command -v`, then `/opt/homebrew/bin`, then `/usr/local/bin`. Exits
with a clear message on stderr (rc 1) when either is missing or
`gh auth token` fails — the agent then reports the server as failed to start
instead of hanging.

```
exec env GITHUB_PERSONAL_ACCESS_TOKEN="$(gh auth token)" \
  github-mcp-server stdio --toolsets repos,issues,pull_requests
```

## Error handling

- `vscode_extensions_apply` reports each failed `--install-extension` with
  `err` and returns 1 at the end so the unit shows as failed, but continues
  through the list.
- `mcp_apply` likewise continues past a failed add/remove, returns 1 at the
  end, and only writes state for operations that succeeded, so the next run
  retries exactly the failed ones.
- Under `--dry-run` every `mcp add/remove` and `code --install-extension` is
  printed via `run_cmd`; state and detection are read-only.
- `mcp_agent_has` for gemini treats a missing or unparsable
  `~/.gemini/settings.json` as "absent".

## Docs

- README: rows for `vscode` (Development) and `mcp-servers` (AI) in the apps
  table; rows for `dotfiles/mcp-servers.conf` and `bin/github-mcp.sh` in the
  managed-files table; the agent-tooling paragraph mentions Gemini as a third
  skills target; the "Claude Code context audit" section gains one sentence
  on MCP roster changes.
- `docs/howto.md`: sections `vscode` (which extension goes with which agent,
  sign-in per extension, zap removes extensions) and `mcp-servers` (roster
  format, how to add a server, `gh auth login` prerequisite, widening the
  GitHub toolsets, verifying with `<cli> mcp list`).
- `docs/agent-skills-report.md` is not touched; the skills inventory in
  `claude-nyamaste-studios-strategy/tech/skills.md` gets a follow-up note
  outside this repo.

## Testing

Offline, under stock bash 3.2, through `tests/run.sh`:

- `tests/fakes/code`: logs every call; `--list-extensions` prints the
  contents of `$FAKE_CODE_EXTENSIONS`; `--install-extension X` appends X to
  it. `FAKE_CODE_FAIL=1` makes install exit 1.
- `tests/fakes/claude`, `tests/fakes/codex`, `tests/fakes/gemini`: log every
  call; `mcp get NAME` exits by presence in a per-agent fake store file;
  `mcp add`/`mcp remove` update that store (gemini's fake writes a real
  `~/.gemini/settings.json` so the JSON detection path is exercised).
- `tests/test_vscode.sh`: mapping shape; apply installs only extensions for
  installed agents (agent installed-ness stubbed by overriding
  `claude_code_installed` etc.); already-present extensions are not
  reinstalled; failure returns 1 but continues; dry-run prints without
  calling install.
- `tests/test_mcp.sh`: roster parsing (comments, blank lines, `~/`
  expansion, bad names rejected); per-agent add-command shape for stdio and
  http; first apply adds to every ready agent and writes state; second apply
  is a no-op; changed record removes then re-adds; dropped roster name is
  removed; user-added servers (not in state) are untouched; not-ready agent
  is skipped; `mcp_remove_all` empties the state; dry-run.
- `tests/test_skills_reconcile.sh` and `tests/lib.sh`: the sandbox gains
  `~/.gemini/skills`, the fake `npx` links into it for agent `gemini-cli`,
  and a `*` roster now passes `-a claude-code codex gemini-cli`.
- `tests/test_units.sh`: `vscode`, `mcp-servers` discovered with the right
  categories; alphabetical position of `mcp-servers` between `gemini-cli`
  and `vscode` asserted, since Decision 5 depends on it.
- Manual, on the primary machine after merge: `./run.sh --apps <current
  selection>,vscode,mcp-servers`, then `claude mcp list`, `codex mcp list`,
  `gemini mcp list`, `gemini skills list`, `code --list-extensions`, and one
  `claude-context-audit.sh` run to record the payload delta.
