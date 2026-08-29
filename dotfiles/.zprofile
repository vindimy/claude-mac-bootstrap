# .profile for zsh and bash
# Managed by ~/Dropbox/Dev/claude-mac-bootstrap (dotfiles/.zprofile); ~/.zprofile is a
# symlink here, created by install.sh.

eval "$(/opt/homebrew/bin/brew shellenv)"
PATH="$PATH:/Users/dv/go/bin"
# uv
export PATH="/Users/dv/.local/bin:$PATH"

export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export PATH="$ANDROID_HOME/platform-tools:$PATH"

# Daily sweep: keep Dropbox from syncing .git dirs (prevents git index corruption).
# Runs at most once per 24h, in the background. Real script lives in this repo
# (bin/dropbox-ignore-git.sh); install.sh symlinks it into ~/.local/bin. On a machine
# where the symlink is missing/dangling, this block is a silent no-op.
if [ -x "$HOME/.local/bin/dropbox-ignore-git.sh" ]; then
  _dbig_stamp="$HOME/.local/state/dropbox-ignore-git.stamp"
  if [ ! -f "$_dbig_stamp" ] || [ -n "$(find "$_dbig_stamp" -mtime +0 2>/dev/null)" ]; then
    mkdir -p "$HOME/.local/state" && touch "$_dbig_stamp"
    ("$HOME/.local/bin/dropbox-ignore-git.sh" >> "$HOME/Library/Logs/dropbox-ignore-git.log" 2>&1 &)
  fi
  unset _dbig_stamp
fi
