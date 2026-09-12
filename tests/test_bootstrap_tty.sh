#!/bin/bash
# run.sh's `curl | bash` reattach must hand children the terminal's real
# device, not a /dev/tty clone — Bun-based CLIs (`claude`) die with
# "EINVAL: invalid argument, kqueue" on an inherited /dev/tty fd.
. "$(dirname "$0")/lib.sh"
setup_sandbox
# shellcheck source=lib/tty.sh
. "$REPO_ROOT/lib/tty.sh"

# assert_run_sh_has needle label -- greps rather than diffing the whole file
# so a failure prints the missing line, not all of run.sh.
assert_run_sh_has() {
  if grep -qF -- "$1" "$REPO_ROOT/run.sh"; then
    PASSES=$((PASSES + 1))
  else
    FAILS=$((FAILS + 1))
    printf 'FAIL %s\n  missing from run.sh: [%s]\n' "$2" "$1" >&2
  fi
}

# The call site must go through the helper and keep a fallback.
# shellcheck disable=SC2016  # matching run.sh's source text, not expanding it
assert_run_sh_has '. "$REPO_DIR/lib/tty.sh"' "run.sh sources the tty helper"
# shellcheck disable=SC2016
assert_run_sh_has 'exec "$REPO_DIR/run.sh" ${1+"$@"} <"$TTY_DEV"' "run.sh reattaches by device path"
# shellcheck disable=SC2016
assert_run_sh_has 'exec "$REPO_DIR/run.sh" ${1+"$@"} </dev/tty' "run.sh keeps the /dev/tty fallback"

# assert_tty_shape out label -- a resolved path names a specific terminal,
# never the bare /dev/tty clone and never `tty`'s "not a tty" stdout chatter.
# Only the shape is checked: macOS devfs drops a /dev/ttysNNN node as soon as
# the pty is released, so a path resolved in a child no longer stats here.
assert_tty_shape() {
  case "$1" in
    /dev/tty) assert_eq "a specific terminal device" "/dev/tty (the bare clone)" "$2" ;;
    /dev/tty?*) PASSES=$((PASSES + 1)) ;;
    *) assert_eq "/dev/tty<something>" "$1" "$2" ;;
  esac
}

# Whether a terminal is attached depends on how the suite was started, so
# assert the contract that holds either way.
if tty_device; then
  assert_tty_shape "$TTY_DEV" "resolved path names a specific terminal, not /dev/tty"
  assert_ok "resolved path is a live character device" test -c "$TTY_DEV"
else
  assert_eq "" "$TTY_DEV" "with no terminal attached, TTY_DEV is cleared"
fi

# Regression for the real shape of the bug: stdin is a drained pipe (as under
# `curl | bash`) while stdout/stderr still point at the terminal. tty_device
# must recover /dev/ttysNNN from those rather than yield the /dev/tty clone.
if command -v python3 >/dev/null 2>&1; then
  out="$(python3 - "$REPO_ROOT" <<'PY' 2>/dev/null
import os, pty, select, sys
# ': | { ... }' hands the block a drained pipe on stdin, as `curl | bash` does.
cmd = ': | { . "%s/lib/tty.sh"; tty_device && echo "$TTY_DEV"; }' % sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", "-c", cmd])
buf = b""
while True:
    if not select.select([fd], [], [], 10)[0]:
        break
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
os.waitpid(pid, 0)
print(buf.decode(errors="replace").strip())
PY
  )"
  assert_tty_shape "$out" "curl|bash stdin: resolves to the slave device"
else
  echo "note: python3 unavailable — skipping the pty case" >&2
fi

finish
