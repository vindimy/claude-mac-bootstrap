#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
# The launcher runs from an agent's environment: give it a fake gh and a
# fake server on PATH and check what it execs.
mkdir -p "$SANDBOX/bin"
cat >"$SANDBOX/bin/gh" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "auth token" ]; then printf '%s\n' "${FAKE_GH_TOKEN-tok123}"; exit "${FAKE_GH_RC:-0}"; fi
exit 2
EOF
cat >"$SANDBOX/bin/github-mcp-server" <<'EOF'
#!/bin/bash
printf '%s %s\n' "$GITHUB_PERSONAL_ACCESS_TOKEN" "$*"
EOF
chmod +x "$SANDBOX/bin/gh" "$SANDBOX/bin/github-mcp-server"
export PATH="$SANDBOX/bin:$PATH"
w="$REPO_ROOT/bin/github-mcp.sh"

assert_ok "launcher is executable" test -x "$w"
assert_eq "tok123 stdio --toolsets repos,issues,pull_requests" "$("$w")" "token via env; stdio with limited toolsets"
out="$(FAKE_GH_RC=1 "$w" 2>&1)"; rc=$?
assert_eq "1" "$rc" "gh not logged in -> rc 1"
assert_contains "$out" "gh auth login" "gh not logged in -> hint"
# shellcheck disable=SC1007  # deliberately empty: sets FAKE_GH_TOKEN to "" for this run
out="$(FAKE_GH_TOKEN= "$w" 2>&1)"; rc=$?
assert_eq "1" "$rc" "empty token -> rc 1"
assert_contains "$out" "gh auth login" "empty token -> hint"
finish
