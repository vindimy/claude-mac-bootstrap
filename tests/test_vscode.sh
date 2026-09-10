#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
discover_apps
code_log() { cat "$FAKE_CODE_LOG"; }

# ---- driver ----
assert_eq "$TESTS_DIR/fakes/code" "$(vscode_code_bin)" "code CLI resolved from PATH"
printf 'Anthropic.claude-code\n' >"$FAKE_CODE_EXTENSIONS"
assert_ok "installed, case-insensitive" vscode_ext_installed anthropic.claude-code
assert_fail "not installed" vscode_ext_installed openai.chatgpt
assert_ok "cached list honoured" vscode_ext_installed openai.chatgpt "openai.chatgpt"
assert_fail "cached list is authoritative" vscode_ext_installed anthropic.claude-code "openai.chatgpt"
: >"$FAKE_CODE_LOG"
vscode_ext_install openai.chatgpt
assert_contains "$(code_log)" "--install-extension openai.chatgpt" "install calls the CLI"
assert_ok "installed after install" vscode_ext_installed openai.chatgpt
out="$(DRY_RUN=1 vscode_ext_install google.geminicodeassist)"
assert_contains "$out" "[dry-run] $TESTS_DIR/fakes/code --install-extension google.geminicodeassist" "dry-run install prints"
assert_fail "dry-run did not install" vscode_ext_installed google.geminicodeassist

finish
