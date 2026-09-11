#!/bin/bash
# Mark git internals and rebuildable build/dependency dirs under Dropbox as
# Dropbox-ignored (com.dropbox.ignored=1): sync can then never corrupt a git
# index, and never churns on node_modules & co. Logs only newly flagged dirs.
# Runs under stock macOS bash 3.2. DROPBOX_DIR overrides the folder (tests).
DB="${DROPBOX_DIR:-$HOME/Library/CloudStorage/Dropbox}"
# No Dropbox folder on this machine — nothing to protect, exit silently.
[ -d "$DB" ] || exit 0

# Names that only ever mean "generated, rebuildable" — ignored wherever found.
ALWAYS=".git node_modules .wrangler .venv venv __pycache__ .pytest_cache
  .mypy_cache .ruff_cache .tox .gradle DerivedData Pods .next .nuxt .svelte-kit
  .turbo .parcel-cache .cache .dart_tool .expo .terraform"
# Names too generic to trust alone — ignored only beside a project manifest.
GENERIC="build dist out target coverage"
MARKERS="package.json pyproject.toml requirements.txt build.gradle
  build.gradle.kts settings.gradle settings.gradle.kts Cargo.toml pom.xml
  Podfile go.mod composer.json wrangler.toml wrangler.jsonc wrangler.json"

# is_generic <name>
is_generic() {
  case " $GENERIC " in *" $1 "*) return 0 ;; esac
  return 1
}

# has_marker <dir>: a project manifest sits directly inside <dir>.
has_marker() {
  local m
  for m in $MARKERS; do
    [ -e "$1/$m" ] && return 0
  done
  return 1
}

# find expression: -type d ( -name a -o -name b ... ) -prune -print
names=()
for n in $ALWAYS $GENERIC; do
  [ "${#names[@]}" -gt 0 ] && names+=(-o)
  names+=(-name "$n")
done

find "$DB" -type d \( "${names[@]}" \) -prune -print 2>/dev/null | while IFS= read -r d; do
  if is_generic "$(basename "$d")" && ! has_marker "$(dirname "$d")"; then
    continue
  fi
  if [ "$(xattr -p com.dropbox.ignored "$d" 2>/dev/null)" != "1" ]; then
    xattr -w com.dropbox.ignored 1 "$d" && echo "$(date '+%Y-%m-%d %H:%M:%S') ignored: $d"
  fi
done
