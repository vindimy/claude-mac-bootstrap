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

# Agents a "*" roster entry resolves to: every known agent whose home dir
# exists, in this order. Passed explicitly as -a because the CLI's own
# auto-selection (add -g -y with no -a) appends every ".agents/skills" agent,
# including ones with no global dir, and reports them as failures
# (vercel-labs/skills#1424, open since 2026-06).
SKILLS_KNOWN_AGENTS="claude-code codex gemini-cli"

skills_installed_agents() {
  local a out=""
  for a in $SKILLS_KNOWN_AGENTS; do
    if [ -d "$(skills_agent_home "$a")" ]; then out="$out $a"; fi
  done
  printf '%s\n' "${out# }"
}

# 0 when agents is "*" or every named agent is installed (its home dir exists).
skills_agents_ready() {
  local a
  if [ "$1" = "*" ]; then return 0; fi
  for a in $1; do
    if [ ! -d "$(skills_agent_home "$a")" ]; then return 1; fi
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
  if [ "$agents" = "*" ]; then agents="$(skills_installed_agents)"; fi
  # -a is variadic like -s: space-separated names (a comma list is rejected)
  # shellcheck disable=SC2206
  if [ -n "$agents" ]; then aflag=(-a $agents); fi
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
    for d in "$SKILLS_STORE/$name" "$HOME/.claude/skills/$name" "$HOME/.codex/skills/$name" "$HOME/.gemini/skills/$name"; do
      if [ -e "$d" ] || [ -L "$d" ]; then
        log "removing untracked local skill copy: $d"
        run_cmd rm -rf "$d"
      fi
    done
  done
}

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
