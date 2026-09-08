#!/bin/bash
# Run every tests/test_*.sh under the stock macOS bash (3.2) and shellcheck
# the sources. Exit 1 if anything fails.
set -u
cd "$(dirname "$0")/.." || exit 1
rc=0
tests=""
for t in tests/test_*.sh; do
  [ -e "$t" ] && tests="$tests $t"
done
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck lib/*.sh apps/*.sh run.sh update.sh install.sh tests/lib.sh tests/run.sh tests/fakes/npx $tests || rc=1
else
  echo "warning: shellcheck not installed (brew install shellcheck) — skipping lint" >&2
fi
for t in tests/test_*.sh; do
  [ -e "$t" ] || continue
  /bin/bash "$t" || rc=1
done
exit "$rc"
