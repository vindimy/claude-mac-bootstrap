#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
s="$REPO_ROOT/bin/socks-proxy.sh"
# Point every knob at the sandbox so nothing touches the real machine, and
# aim the "tunnel" at a port nothing listens on so the offline paths run.
export MAC_BOOTSTRAP_HOME="$SANDBOX/state"
export VSCODE_SETTINGS="$SANDBOX/settings.json"
export SOCKS_PORT=59571
export BRIDGE_PORT=59572

assert_ok "script is executable" test -x "$s"

out="$("$s" --help)"
assert_contains "$out" "up [--gui]" "help lists up"
assert_contains "$out" "verify" "help lists verify"

"$s" bogus >/dev/null 2>&1; rc=$?
assert_eq "2" "$rc" "unknown command -> rc 2"

# The bridge speaks HTTP to the tools: a SOCKS URL here would silently break
# Copilot and be ignored outright by Codex.
out="$("$s" env)"
assert_contains "$out" 'export HTTPS_PROXY="http://127.0.0.1:59572"' "env exports the bridge URL"
assert_contains "$out" 'export ALL_PROXY="http://127.0.0.1:59572"' "env sets ALL_PROXY for Codex"
assert_not_contains "$out" "socks" "env never hands a SOCKS URL to a tool"
assert_contains "$out" 'export NO_PROXY="localhost,127.0.0.1,::1"' "loopback bypasses the proxy"
out="$(NO_PROXY_LIST=localhost "$s" env)"
assert_contains "$out" 'export no_proxy="localhost"' "NO_PROXY_LIST is honoured"

# forward-socks5 is what keeps DNS off this machine; socks4 would resolve locally.
out="$("$s" config)"
assert_contains "$out" "forward-socks5 / 127.0.0.1:59571 ." "bridge forwards to the tunnel with remote DNS"
assert_contains "$out" "listen-address 127.0.0.1:59572" "bridge listens on loopback only"
assert_not_contains "$out" "actionsfile" "no filtering: privoxy forwards bytes unchanged"

# Nothing may be configured while the tunnel is down — that would send the
# agents at a dead proxy, or worse, leave them connecting directly.
out="$("$s" up 2>&1)"; rc=$?
assert_eq "1" "$rc" "up without a tunnel -> rc 1"
assert_contains "$out" "ssh -D 59571" "up without a tunnel names the ssh command"
assert_ok "up without a tunnel writes no settings" test ! -f "$VSCODE_SETTINGS"

out="$("$s" verify 2>&1)"; rc=$?
assert_eq "1" "$rc" "verify without a tunnel -> rc 1"

out="$("$s" status)"
assert_contains "$out" "SSH SOCKS tunnel       DOWN" "status reports the tunnel down"
assert_contains "$out" "HTTP bridge            DOWN" "status reports the bridge down"

# down is safe to run when nothing is up, and leaves unrelated settings alone.
printf '{"editor.fontSize":13}\n' >"$VSCODE_SETTINGS"
assert_ok "down is idempotent" "$s" down
assert_eq '13' "$(jq -r '."editor.fontSize"' "$VSCODE_SETTINGS")" "down keeps unrelated settings"
assert_eq 'null' "$(jq -r '."http.proxy"' "$VSCODE_SETTINGS")" "down removes http.proxy"

finish
