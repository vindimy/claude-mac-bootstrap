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
