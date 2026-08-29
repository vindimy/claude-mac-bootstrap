#!/bin/zsh
# Mark all .git dirs in Dropbox as Dropbox-ignored (com.dropbox.ignored=1)
# so Dropbox sync can never corrupt a git index. Logs only newly flagged dirs.
DB="$HOME/Library/CloudStorage/Dropbox"
find "$DB" -type d -name .git -prune 2>/dev/null | while IFS= read -r d; do
  if [[ "$(xattr -p com.dropbox.ignored "$d" 2>/dev/null)" != "1" ]]; then
    xattr -w com.dropbox.ignored 1 "$d" && echo "$(date '+%Y-%m-%d %H:%M:%S') ignored: $d"
  fi
done
