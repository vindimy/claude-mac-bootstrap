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
# Per-process cache of upstream listings. Keyed by $$ (the entry point's PID,
# which command substitutions inherit) so a subshell's fetch is reused.
SKILLS_CACHE_DIR="${SKILLS_CACHE_DIR:-${TMPDIR:-/tmp}/mac-bootstrap-skills.$$}"

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

skills_conf_write() { # var value put|delete
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
  mkdir -p "$SKILLS_CACHE_DIR"
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
  python3 - "$SKILLS_LOCK" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:  # unreadable lock: warn, act as empty
    sys.stderr.write("warning: cannot read %s: %s\n" % (sys.argv[1], e))
    sys.exit(0)
for n, v in sorted(d.get("skills", {}).items()):
    if v.get("source") == sys.argv[2]:
        print(n)
PY
}

skills_lock_has() { # name -> 0 if any source tracks it
  if [ ! -f "$SKILLS_LOCK" ] || ! command -v python3 >/dev/null 2>&1; then return 1; fi
  python3 - "$SKILLS_LOCK" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in d.get("skills", {}) else 1)
PY
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

# ---- reconcile ---------------------------------------------------------------

# skills_reconcile repo agents selected
#   selected: space-separated names, "*" (track the whole repo), or "".
# add refreshes installed skills in place (verified 2026-09-08), so this is
# both install and update. Stale = lock names for this repo that are not
# selected (or, for "*", not published upstream any more) — removed by name.
skills_reconcile() {
  local repo="$1" agents="$2" selected="$3" rc=0 name stale="" lock upstream
  local aflag=() # bash 3.2: guard the expansion below
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
