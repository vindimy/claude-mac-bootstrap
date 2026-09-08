#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
ROSTER="acme/tools|*|alpha gamma
acme/suite|codex|*"
UNIT="Test unit"
# shellcheck disable=SC2012
store_ls() { ls "$HOME/.agents/skills" | tr '\n' ' ' | sed 's/ $//'; }

# --- non-interactive first install: defaults, saved, installed
assert_fail "not installed before" skills_unit_installed "$UNIT" "$ROSTER"
assert_ok "install" skills_unit_install "$UNIT" "$ROSTER" ""
assert_eq "alpha gamma" "$(skills_conf_get acme/tools)" "defaults saved (names)"
assert_eq "*" "$(skills_conf_get acme/suite)" "defaults saved (star stays star)"
assert_eq "alpha gamma one two" "$(store_ls)" "store after install"
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
assert_contains "$(npx_log)" "add acme/tools -g -y -a claude-code codex -s beta" "update installs saved list"
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
rm -rf "$HOME/.codex"
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
assert_eq "zeta" "$(store_ls)" "only the unit's skills removed"
assert_eq "beta gamma" "$(skills_conf_get acme/tools)" "conf kept"
assert_fail "not installed after uninstall" skills_unit_installed "$UNIT" "$ROSTER"
assert_ok "uninstall zap" skills_unit_uninstall "$UNIT" "$ROSTER" zap
assert_fail "zap drops conf line" skills_conf_get acme/tools
assert_fail "zap drops conf line (2)" skills_conf_get acme/suite

# --- offline first install: explicit defaults still install, star repo installs with -s *
unset SKILLS_SYNCED_UNITS
: >"$FAKE_NPX_LOG"
rm -rf "$SKILLS_CACHE_DIR"   # earlier listings are cached per process; force a real (failing) fetch
export NON_INTERACTIVE=0
screen="$(FAKE_NPX_LIST_FAIL=1 skills_unit_install "$UNIT" "$ROSTER" "" 2>&1 >/dev/null)"
assert_not_contains "$screen" "upstream)" "offline: no checklist shown"
assert_contains "$screen" "cannot list upstream" "offline: warning shown"
assert_eq "alpha gamma" "$(skills_conf_get acme/tools)" "offline falls back to defaults"
assert_contains "$(npx_log)" "add acme/suite -g -y -a codex -s *" "offline star still installs"
finish
