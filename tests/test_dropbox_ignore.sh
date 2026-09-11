#!/bin/bash
# bin/dropbox-ignore-git.sh: flags git internals and build/dependency dirs
# under DROPBOX_DIR with com.dropbox.ignored=1, leaves everything else alone.
. "$(dirname "$0")/lib.sh"
setup_sandbox

if ! command -v xattr >/dev/null 2>&1; then
  echo "$(basename "$0"): xattr not available, skipping"
  exit 0
fi

SWEEP="$REPO_ROOT/bin/dropbox-ignore-git.sh"
export DROPBOX_DIR="$SANDBOX/Dropbox"

flag() { xattr -p com.dropbox.ignored "$1" 2>/dev/null || echo none; }

# no Dropbox folder: silent no-op
out="$(/bin/bash "$SWEEP" 2>&1)"; rc=$?
assert_eq "0" "$rc" "missing folder exits 0"
assert_eq "" "$out" "missing folder prints nothing"

P="$DROPBOX_DIR/Dev/proj"
mkdir -p "$P/.git" "$P/node_modules/pkg/node_modules" "$P/.wrangler" "$P/.venv" \
  "$P/dist" "$P/build" "$P/src" \
  "$P/ios/App/Pods" "$P/ios/App/build" "$P/ios/DerivedData" \
  "$P/android/.gradle" "$P/android/app/build" \
  "$DROPBOX_DIR/Books/build" "$DROPBOX_DIR/Books/dist/notes" \
  "$DROPBOX_DIR/Family Room/out"
touch "$P/package.json" "$P/ios/App/Podfile" "$P/android/app/build.gradle"

out="$(/bin/bash "$SWEEP" 2>&1)"; rc=$?
assert_eq "0" "$rc" "sweep exits 0"

# always-ignored names, anywhere
assert_eq "1" "$(flag "$P/.git")" ".git flagged"
assert_eq "1" "$(flag "$P/node_modules")" "node_modules flagged"
assert_eq "1" "$(flag "$P/.wrangler")" ".wrangler flagged"
assert_eq "1" "$(flag "$P/.venv")" ".venv flagged"
assert_eq "1" "$(flag "$P/ios/App/Pods")" "Pods flagged"
assert_eq "1" "$(flag "$P/ios/DerivedData")" "DerivedData flagged"
assert_eq "1" "$(flag "$P/android/.gradle")" ".gradle flagged"
# generic names only beside a project manifest
assert_eq "1" "$(flag "$P/dist")" "dist beside package.json flagged"
assert_eq "1" "$(flag "$P/build")" "build beside package.json flagged"
assert_eq "1" "$(flag "$P/ios/App/build")" "build beside Podfile flagged"
assert_eq "1" "$(flag "$P/android/app/build")" "build beside build.gradle flagged"
assert_eq "none" "$(flag "$DROPBOX_DIR/Books/build")" "build without manifest untouched"
assert_eq "none" "$(flag "$DROPBOX_DIR/Books/dist")" "dist without manifest untouched"
assert_eq "none" "$(flag "$DROPBOX_DIR/Family Room/out")" "out without manifest untouched"
# ordinary dirs and pruned subtrees untouched
assert_eq "none" "$(flag "$P/src")" "source dir untouched"
assert_eq "none" "$(flag "$P")" "project root untouched"
assert_eq "none" "$(flag "$P/node_modules/pkg/node_modules")" "nested node_modules pruned, parent covers it"
# log: one line per newly flagged dir, nothing for skipped ones
assert_contains "$out" "ignored: $P/node_modules" "log names flagged dir"
assert_not_contains "$out" "Books/build" "log omits skipped dir"
assert_eq "11" "$(printf '%s\n' "$out" | grep -c 'ignored: ')" "11 dirs flagged"

# idempotent: second run flags nothing
out="$(/bin/bash "$SWEEP" 2>&1)"
assert_eq "" "$out" "second run prints nothing"

finish
