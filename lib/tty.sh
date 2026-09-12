#!/bin/bash
# Terminal helpers. Kept in its own file (not common.sh) so run.sh's
# standalone bootstrap can source it from the fresh clone before the rest of
# the libs exist.

# tty_device -> sets $TTY_DEV to the terminal's real device path
# (/dev/ttysNNN) and returns 0; returns 1 with $TTY_DEV empty when no
# standard fd still points at a terminal.
#
# Callers must reattach stdin through this rather than redirecting from
# /dev/tty. Bun cannot kqueue-poll a freshly opened /dev/tty clone: a child
# that inherits one dies on startup with
#     EINVAL: invalid argument, kqueue ... at pull
# which takes out every Bun-based CLI a unit shells out to (`claude`, and so
# the whole claude-code / claude-plugins pair). An fd opened on the real
# device path polls fine.
#
# ttyname(3) reports "/dev/tty" for an fd opened on /dev/tty, so the path has
# to come from an fd that already points at the terminal. Under `curl | bash`
# that is stdout or stderr — stdin is the pipe.
#
# The answer lands in a global rather than on stdout because $(...) replaces
# stdout with its own pipe: probing the fds inside a command substitution
# would test that pipe instead of the caller's terminal. Bash 3.2 has no
# {var}<&N, so the saved fd number is fixed; 8 is unused elsewhere here.
tty_device() {
  TTY_DEV=""
  local dev
  if [ -t 0 ]; then
    exec 8<&0
  elif [ -t 1 ]; then
    exec 8>&1
  elif [ -t 2 ]; then
    exec 8>&2
  else
    return 1
  fi
  # `tty` prints "not a tty" on stdout, so a failure must not reach $dev.
  dev="$(tty <&8 2>/dev/null)" || dev=""
  exec 8>&-
  case "$dev" in
    /dev/tty) return 1 ;; # the clone, not a device path — unusable
    /dev/?*) ;;
    *) return 1 ;;
  esac
  [ -c "$dev" ] && [ -r "$dev" ] || return 1
  # shellcheck disable=SC2034  # the result: read by callers, not by this file
  TTY_DEV="$dev"
}
