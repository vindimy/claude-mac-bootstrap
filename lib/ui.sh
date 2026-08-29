#!/bin/bash
# Interactive selection UI. Sourced after lib/common.sh; needs discover_apps
# to have populated APP_IDS/APP_NAMES.

# Checklist over all discovered apps, pre-checked from $SELECTED.
# Toggle by number, a=all, n=none, empty input confirms into NEW_SELECTED.
select_apps() {
  local current="$SELECTED" input tok idx id
  while :; do
    log ""
    log "Select apps to manage. Checked apps are installed and kept updated;"
    log "unchecking a previously managed app uninstalls it."
    idx=0
    while [ "$idx" -lt "${#APP_IDS[@]}" ]; do
      id="${APP_IDS[$idx]}"
      if in_list "$id" "$current"; then
        printf '  %2d) [x] %s\n' "$((idx + 1))" "${APP_NAMES[$idx]}"
      else
        printf '  %2d) [ ] %s\n' "$((idx + 1))" "${APP_NAMES[$idx]}"
      fi
      idx=$((idx + 1))
    done
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
