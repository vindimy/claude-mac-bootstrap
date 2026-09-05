#!/bin/bash
# Interactive selection UI. Sourced after lib/common.sh; needs discover_apps
# to have populated APP_IDS/APP_NAMES/APP_CATEGORIES.

# Display order for category headers in the checklist. Categories used by an
# app but absent here (including the "Other" fallback) are appended at the end
# in discovery order.
CATEGORY_ORDER=("AI" "Browsers" "Development" "Creative" "Cloud Storage" "System Tools" "VPN")

category_in_order() {
  local c
  for c in "${CATEGORY_ORDER[@]}"; do
    if [ "$c" = "$1" ]; then return 0; fi
  done
  return 1
}

# print_app_row index current-selection — one numbered checklist line. Numbers
# are the app's discovery index, stable regardless of display grouping.
print_app_row() {
  local mark=" "
  if in_list "${APP_IDS[$1]}" "$2"; then mark=x; fi
  printf '  %2d) [%s] %s\n' "$(($1 + 1))" "$mark" "${APP_NAMES[$1]}"
}

# print_category_group category current-selection — header + rows for one
# category; prints nothing when no app carries it.
print_category_group() {
  local cat="$1" current="$2" idx=0 shown=0
  while [ "$idx" -lt "${#APP_IDS[@]}" ]; do
    if [ "${APP_CATEGORIES[$idx]}" = "$cat" ]; then
      if [ "$shown" = 0 ]; then
        log ""
        log "$cat"
        shown=1
      fi
      print_app_row "$idx" "$current"
    fi
    idx=$((idx + 1))
  done
}

# Checklist over all discovered apps, grouped by APP_CATEGORY and pre-checked
# from $SELECTED. Toggle by number, a=all, n=none, empty input confirms into
# NEW_SELECTED.
select_apps() {
  local current="$SELECTED" input tok idx id cat seen
  local extra_cats=()
  idx=0
  while [ "$idx" -lt "${#APP_IDS[@]}" ]; do
    cat="${APP_CATEGORIES[$idx]}"
    if ! category_in_order "$cat"; then
      seen=0
      for id in ${extra_cats[@]+"${extra_cats[@]}"}; do
        if [ "$id" = "$cat" ]; then seen=1; fi
      done
      if [ "$seen" = 0 ]; then extra_cats+=("$cat"); fi
    fi
    idx=$((idx + 1))
  done
  while :; do
    log ""
    log "Select apps to manage. Checked apps are installed and kept updated;"
    log "unchecking a previously managed app uninstalls it."
    for cat in "${CATEGORY_ORDER[@]}" ${extra_cats[@]+"${extra_cats[@]}"}; do
      print_category_group "$cat" "$current"
    done
    log ""
    printf 'Toggle numbers (space-separated), a=all, n=none, Enter=confirm: '
    read -r input
    case "$input" in
      "")
        # shellcheck disable=SC2034
        NEW_SELECTED="$current"
        return 0
        ;;
      a) current="${APP_IDS[*]}" ;;
      n) current="" ;;
      *)
        # shellcheck disable=SC2086
        for tok in $input; do
          case "$tok" in
            *[!0-9]*)
              warn "not a number: $tok"
              ;;
            *)
              if [ "$tok" -ge 1 ] && [ "$tok" -le "${#APP_IDS[@]}" ]; then
                id="${APP_IDS[$((10#$tok - 1))]}"
                if in_list "$id" "$current"; then
                  current="$(remove_from_list "$id" "$current")"
                else
                  current="$current $id"
                fi
              else
                warn "out of range: $tok"
              fi
              ;;
          esac
        done
        ;;
    esac
  done
}

# Ask keep-vs-zap for one app being uninstalled. Prompt goes to stderr so the
# answer can be captured from stdout. Default (Enter or anything but z) = keep.
prompt_uninstall_mode() {
  local ans
  printf 'Remove %s — keep its settings? [K=keep / z=zap settings too]: ' "$1" >&2
  read -r ans
  case "$ans" in
    z | Z | zap) printf 'zap\n' ;;
    *) printf 'keep\n' ;;
  esac
}
