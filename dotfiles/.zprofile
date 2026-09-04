# .profile for zsh and bash
# Managed by the claude-mac-bootstrap repo (dotfiles/.zprofile); ~/.zprofile is a
# symlink here, created by install.sh.

# Homebrew, wherever it landed (fresh machines may not have it yet).
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if [ -d "$HOME/go/bin" ]; then PATH="$PATH:$HOME/go/bin"; fi
# uv, the claude-code native install, and other user-level tools
export PATH="$HOME/.local/bin:$PATH"

# Toolchains that only some machines carry — silent no-ops elsewhere.
if _jh="$(/usr/libexec/java_home -v 17 2>/dev/null)"; then export JAVA_HOME="$_jh"; fi
unset _jh
if [ -d /opt/homebrew/share/android-commandlinetools ]; then
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  export PATH="$ANDROID_HOME/platform-tools:$PATH"
fi

# Daily sweep: keep Dropbox from syncing .git dirs (prevents git index corruption).
# Runs at most once per 24h, in the background. Real script lives in this repo
# (bin/dropbox-ignore-git.sh); install.sh symlinks it into ~/.local/bin. The sweep
# no-ops on machines without a Dropbox folder, so nothing here assumes Dropbox.
if [ -x "$HOME/.local/bin/dropbox-ignore-git.sh" ]; then
  _dbig_stamp="$HOME/.local/state/dropbox-ignore-git.stamp"
  if [ ! -f "$_dbig_stamp" ] || [ -n "$(find "$_dbig_stamp" -mtime +0 2>/dev/null)" ]; then
    mkdir -p "$HOME/.local/state" && touch "$_dbig_stamp"
    ("$HOME/.local/bin/dropbox-ignore-git.sh" >> "$HOME/Library/Logs/dropbox-ignore-git.log" 2>&1 &)
  fi
  unset _dbig_stamp
fi
