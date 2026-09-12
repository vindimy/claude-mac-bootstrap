#!/bin/bash
# claude-plugins must tell "the CLI says some plugins are missing" apart from
# "the CLI could not answer". Conflating them turned an update into a silent
# reinstall and buried the CLI's own error (the kqueue crash in docs/howto.md).
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
# shellcheck source=/dev/null
. "$REPO_ROOT/apps/claude-plugins.sh"

# A `claude` stub ahead of tests/fakes on PATH, steered by $FAKE_CLAUDE_MODE
# and logging every subcommand it is asked to run.
STUB_DIR="$SANDBOX/stub"
mkdir -p "$STUB_DIR"
export FAKE_CLAUDE_LOG="$SANDBOX/claude.log"
cat >"$STUB_DIR/claude" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_CLAUDE_LOG"
case "$1 $2" in
  "plugin list")
    case "$FAKE_CLAUDE_MODE" in
      crash)
        # what a Bun startup failure looks like: stderr, non-zero, no stdout
        echo 'EINVAL: invalid argument, kqueue' >&2
        exit 1
        ;;
      missing) printf 'superpowers\nfrontend-design\n' ;;
      *) printf '%s\n' $CLAUDE_PLUGINS | sed 's/@.*//' ;;
    esac
    ;;
esac
exit 0
STUB
chmod +x "$STUB_DIR/claude"
export PATH="$STUB_DIR:$PATH"
export CLAUDE_PLUGINS   # the stub echoes the roster back as the installed set
claude_log() { cat "$FAKE_CLAUDE_LOG"; }
reset_log() { : >"$FAKE_CLAUDE_LOG"; }
reset_log

# rc_of fn -- run fn quietly and echo its exit code
rc_of() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# --- claude_plugins_installed: three distinct answers ---------------------
export FAKE_CLAUDE_MODE=ok
assert_eq "0" "$(rc_of claude_plugins_installed)" "full roster installed -> 0"

export FAKE_CLAUDE_MODE=missing
assert_eq "1" "$(rc_of claude_plugins_installed)" "roster gaps -> 1"

export FAKE_CLAUDE_MODE=crash
assert_eq "2" "$(rc_of claude_plugins_installed)" "CLI failure -> 2, not 1"

# The CLI's own diagnostic must reach stderr, not /dev/null.
out="$(claude_plugins_installed 2>&1 >/dev/null)"
assert_contains "$out" "EINVAL: invalid argument, kqueue" "CLI stderr is not swallowed"

# --- claude_plugins_update: a broken CLI must not trigger a reinstall -----
export FAKE_CLAUDE_MODE=crash
reset_log
rc=0
out="$(claude_plugins_update 2>&1)" || rc=$?
assert_eq "1" "$rc" "update fails when the CLI cannot be read"
assert_contains "$out" "refusing to reinstall on a guess" "update explains why it stopped"
assert_not_contains "$(claude_log)" "plugin install" "no reinstall attempted"
assert_not_contains "$(claude_log)" "marketplace add" "no marketplace re-add attempted"

# --- roster gaps still reinstall, as before -------------------------------
export FAKE_CLAUDE_MODE=missing
reset_log
claude_plugins_update >/dev/null 2>&1 || true
assert_contains "$(claude_log)" "plugin install" "roster gaps still reinstall"

# --- a healthy CLI still updates ------------------------------------------
export FAKE_CLAUDE_MODE=ok
reset_log
assert_ok "healthy CLI updates cleanly" claude_plugins_update >/dev/null
assert_contains "$(claude_log)" "plugin marketplace update" "marketplaces updated"
assert_contains "$(claude_log)" "plugin update superpowers@claude-plugins-official" "plugins updated"
assert_not_contains "$(claude_log)" "plugin install" "no reinstall on a healthy CLI"

finish
