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
  if "$@"; then
    PASSES=$((PASSES + 1))
  else
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
  else
    PASSES=$((PASSES + 1))
  fi
}

# Fresh HOME with empty store + agent dirs, isolated config dir, fake npx first
# on PATH, non-interactive by default. Call before load_libs (CONFIG_DIR is
# resolved when lib/common.sh is sourced).
setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.gemini/skills"
  export BOOTSTRAP_CONFIG_DIR="$SANDBOX/config"
  export FAKE_NPX_LOG="$SANDBOX/npx.log"
  : >"$FAKE_NPX_LOG"
  export FAKE_NPX_FIXTURES="$TESTS_DIR/fixtures"
  export FAKE_CODE_LOG="$SANDBOX/code.log"
  export FAKE_CODE_EXTENSIONS="$SANDBOX/code-extensions"
  : >"$FAKE_CODE_LOG"
  : >"$FAKE_CODE_EXTENSIONS"
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
