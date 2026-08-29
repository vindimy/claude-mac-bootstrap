#!/bin/bash
# Idempotent installer: symlink this repo's managed files into place.
# Safe to re-run any time; backs up pre-existing real files as *.pre-bootstrap.bak.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# link <target-in-repo> <destination>
link() {
  local target="$1" dest="$2"
  if [ -L "$dest" ]; then
    if [ "$(readlink "$dest")" = "$target" ]; then
      echo "ok:        $dest"
      return
    fi
    rm "$dest"
  elif [ -e "$dest" ]; then
    mv "$dest" "$dest.pre-bootstrap.bak"
    echo "backed up: $dest -> $dest.pre-bootstrap.bak"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$target" "$dest"
  echo "linked:    $dest -> $target"
}

link "$REPO/dotfiles/.zprofile" "$HOME/.zprofile"
link "$REPO/bin/dropbox-ignore-git.sh" "$HOME/.local/bin/dropbox-ignore-git.sh"

echo "done"
