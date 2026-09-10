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

# ---- unit: mapping ----
assert_eq "3" "$(printf '%s\n' "$VSCODE_AGENT_EXTENSIONS" | grep -c '|')" "three agents mapped"
assert_contains "$VSCODE_AGENT_EXTENSIONS" "claude-code|anthropic.claude-code" "claude mapping"
assert_contains "$VSCODE_AGENT_EXTENSIONS" "codex|openai.chatgpt" "codex mapping"
assert_contains "$VSCODE_AGENT_EXTENSIONS" "gemini-cli|google.gemini-cli-vscode-ide-companion google.geminicodeassist" "gemini gets both extensions"

# ---- unit: apply installs only for installed agents ----
claude_code_installed() { return 0; }
codex_installed() { return 1; }
gemini_cli_installed() { return 0; }
: >"$FAKE_CODE_EXTENSIONS"
: >"$FAKE_CODE_LOG"
assert_ok "apply succeeds" vscode_extensions_apply
assert_contains "$(code_log)" "--install-extension anthropic.claude-code" "claude ext installed"
assert_not_contains "$(code_log)" "openai.chatgpt" "codex not installed -> no ext"
assert_contains "$(code_log)" "--install-extension google.gemini-cli-vscode-ide-companion" "gemini companion installed"
assert_contains "$(code_log)" "--install-extension google.geminicodeassist" "gemini code assist installed"
assert_eq "1" "$(grep -c -- '--list-extensions' "$FAKE_CODE_LOG")" "listing read once per pass"

# second pass: everything present, nothing installed
: >"$FAKE_CODE_LOG"
vscode_extensions_apply
assert_not_contains "$(code_log)" "--install-extension" "present extensions not reinstalled"

# a failed install is reported, the pass continues, rc is 1
: >"$FAKE_CODE_EXTENSIONS"
: >"$FAKE_CODE_LOG"
export FAKE_CODE_FAIL=1
assert_fail "failed install returns 1" vscode_extensions_apply
assert_eq "3" "$(grep -c -- '--install-extension' "$FAKE_CODE_LOG")" "keeps going after a failure"
unset FAKE_CODE_FAIL

# dry-run prints the installs and changes nothing
: >"$FAKE_CODE_LOG"
out="$(DRY_RUN=1 vscode_extensions_apply)"
assert_contains "$out" "[dry-run] $TESTS_DIR/fakes/code --install-extension anthropic.claude-code" "dry-run prints install"
assert_not_contains "$(code_log)" "--install-extension" "dry-run installs nothing"

# without a code CLI: dry-run explains, real run fails
vscode_code_bin() { return 1; }
out="$(DRY_RUN=1 vscode_extensions_apply)"
assert_contains "$out" "[dry-run] install agent extensions once VS Code is present" "dry-run without VS Code"
assert_fail "no code CLI -> rc 1" vscode_extensions_apply

finish
