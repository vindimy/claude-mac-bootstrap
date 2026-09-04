#!/bin/bash
# Idempotent installer: symlink this repo's managed files into place.
# Safe to re-run any time; backs up pre-existing real files as *.pre-bootstrap.bak.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Symlinks must anchor to the main checkout, never a linked git worktree — worktrees
# are ephemeral, and a symlink into one dangles once the worktree is removed
# (this broke ~/.zprofile, and with it brew/claude PATH, on 2026-08-28).
git_dir="$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null || true)"
common_dir="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
  REPO="$(dirname "$common_dir")"
  echo "note: running from a git worktree; anchoring symlinks to main checkout: $REPO"
fi

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
# Same file serves bash login shells (it is plain POSIX sh).
link "$REPO/dotfiles/.zprofile" "$HOME/.profile"
link "$REPO/bin/dropbox-ignore-git.sh" "$HOME/.local/bin/dropbox-ignore-git.sh"

echo "done"
