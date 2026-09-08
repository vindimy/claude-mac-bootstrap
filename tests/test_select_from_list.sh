#!/bin/bash
. "$(dirname "$0")/lib.sh"
setup_sandbox
load_libs
ITEMS="$(printf 'alpha\tFirst\nbeta\tSecond\ngamma\tThird')"

sel="$(printf '\n' | select_from_list "T" "$ITEMS" "alpha gamma" "" 2>/dev/null)"
assert_eq "alpha gamma" "$sel" "Enter confirms the pre-checked set"

sel="$(printf '2\n\n' | select_from_list "T" "$ITEMS" "alpha gamma" "" 2>/dev/null)"
assert_eq "*" "$sel" "checking the last unchecked item yields *"

sel="$(printf '1\n\n' | select_from_list "T" "$ITEMS" "*" "" 2>/dev/null)"
assert_eq "beta gamma" "$sel" "unchecking one from * yields explicit list"

sel="$(printf 'n\n\n' | select_from_list "T" "$ITEMS" "*" "" 2>/dev/null)"
assert_eq "" "$sel" "n clears everything"

sel="$(printf 'a\n\n' | select_from_list "T" "$ITEMS" "" "" 2>/dev/null)"
assert_eq "*" "$sel" "a selects everything"

sel="$(printf '3 1\n\n' | select_from_list "T" "$ITEMS" "" "" 2>/dev/null)"
assert_eq "alpha gamma" "$sel" "output keeps upstream order regardless of toggle order"

sel="$(printf '' | select_from_list "T" "$ITEMS" "beta" "" 2>/dev/null)"
assert_eq "beta" "$sel" "EOF confirms"

screen="$(printf '\n' | select_from_list "Title here" "$ITEMS" "alpha" "gamma" 2>&1 >/dev/null)"
assert_contains "$screen" "Title here" "title shown"
assert_contains "$screen" "1) [x] alpha" "checked row"
assert_contains "$screen" "2) [ ] beta" "unchecked row"
assert_contains "$screen" "(new)" "new tag shown"
assert_contains "$screen" "First" "description shown"
assert_contains "$screen" "1 of 3 selected" "count line"
screen="$(printf '\n' | select_from_list "T" "$ITEMS" "*" "" 2>&1 >/dev/null)"
assert_contains "$screen" 'saved as "*"' "star notice when all checked"

screen="$(printf '9 x\n\n' | select_from_list "T" "$ITEMS" "" "" 2>&1 >/dev/null)"
assert_contains "$screen" "out of range: 9" "range warning"
assert_contains "$screen" "not a number: x" "number warning"
finish
