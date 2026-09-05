#!/bin/bash
# shellcheck disable=SC2034
# macOS Performance Tuning — a managed set of settings that keep the machine
# and its external disks awake on AC power and switch off features that burn
# CPU, memory and disk in the background. Same contract as hardening:
# install applies, update re-applies (drift correction), installed is a
# compliance check, uninstall zap restores macOS defaults. TRIM, the Spotlight
# cache exclusion and Time Machine snapshots are reported, not changed. Design:
# docs/superpowers/specs/2026-09-04-macos-hardening-design.md
APP_NAME="macOS Performance Tuning"
APP_CATEGORY="System Tools"
APP_NOTE="Needs sudo. On AC power: never sleep, disks never sleep, Power Nap off (battery: disks never sleep, rest untouched). Spotlight indexing off on external volumes. Off: Siri, Apple Intelligence (macOS 15+), Photos/media analysis agents, Handoff, crash dialogs and analytics upload. Siri/Spotlight suggestions, TRIM and ~/Library/Caches indexing are reported with manual steps (docs/howto.md). Log out or restart for everything to take effect."

PERF_UID="$(id -u)"
PERF_AGENTS="com.apple.Siri.agent com.apple.photoanalysisd com.apple.mediaanalysisd"
PERF_AI_DOMAIN=com.apple.CloudSubscriptionFeatures.optIn
PERF_HANDOFF_DOMAIN=com.apple.coreservices.useractivityd
PERF_DIAG_PLIST="/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"
# Apple silicon defaults recorded on Sonoma 14.8 (MacBook Air M3); used by zap.
PERF_PMSET_DEFAULT_AC="sleep 1 disksleep 10 powernap 1"
PERF_PMSET_DEFAULT_BATT="disksleep 10"

perf_macos_major() { sw_vers -productVersion | cut -d. -f1; }

# ---- Power -------------------------------------------------------------------

perf_has_battery() { pmset -g custom 2>/dev/null | grep -q '^Battery Power:'; }

# perf_pmset_is "AC Power"|"Battery Power" key value
perf_pmset_is() {
  local got
  got="$(pmset -g custom 2>/dev/null | awk -v sec="$1:" -v key="$2" '
    $0 == sec { on = 1; next }
    /^[A-Za-z].*:$/ { on = 0 }
    on && $1 == key { print $2 }')"
  [ "$got" = "$3" ]
}

perf_power_apply() {
  # disksleep 0 stops macOS spinning disks down; drives whose firmware has its
  # own idle timer still sleep on their own (vendor tool needed for those).
  run_cmd sudo pmset -c sleep 0 disksleep 0 powernap 0 || return 1
  if perf_has_battery; then
    run_cmd sudo pmset -b disksleep 0 || return 1
  fi
  return 0
}

perf_power_ok() {
  perf_pmset_is "AC Power" sleep 0 || return 1
  perf_pmset_is "AC Power" disksleep 0 || return 1
  perf_pmset_is "AC Power" powernap 0 || return 1
  if perf_has_battery; then perf_pmset_is "Battery Power" disksleep 0 || return 1; fi
  return 0
}

perf_power_revert() {
  # shellcheck disable=SC2086
  run_cmd sudo pmset -c $PERF_PMSET_DEFAULT_AC
  if perf_has_battery; then
    # shellcheck disable=SC2086
    run_cmd sudo pmset -b $PERF_PMSET_DEFAULT_BATT
  fi
}

# ---- Spotlight on external volumes ----------------------------------------------

# Mounted volumes other than the boot volume (whose /Volumes entry is a
# symlink to /). Re-run on every update so newly attached drives get covered.
perf_external_volumes() {
  local v rootdev
  rootdev="$(stat -f %d /)"
  for v in /Volumes/*; do
    if [ ! -d "$v" ] || [ -L "$v" ]; then continue; fi
    if [ "$(stat -f %d "$v" 2>/dev/null)" = "$rootdev" ]; then continue; fi
    printf '%s\n' "$v"
  done
}

# perf_spotlight_externals on|off
perf_spotlight_externals() {
  local v
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    run_cmd sudo mdutil -i "$1" "$v" || warn "performance: mdutil -i $1 failed on $v"
  done <<EOF
$(perf_external_volumes)
EOF
  return 0
}

perf_spotlight_ok() {
  local v
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    case "$(mdutil -s "$v" 2>/dev/null)" in
      *disabled*) ;;
      *) return 1 ;;
    esac
  done <<EOF
$(perf_external_volumes)
EOF
  return 0
}

# ---- Apple Intelligence (macOS 15+) -------------------------------------------------

# The opt-in key is a numeric feature id that changes across macOS updates, so
# it is read back from the domain instead of hardcoded.
perf_ai_feature_id() {
  defaults read "$PERF_AI_DOMAIN" 2>/dev/null \
    | sed -n 's/^ *"\{0,1\}\([0-9][0-9]*\)"\{0,1\} = .*/\1/p' | head -1
}

perf_ai_apply() {
  local id
  if [ "$(perf_macos_major)" -lt 15 ]; then
    log "performance: Apple Intelligence does not exist on macOS $(sw_vers -productVersion) — skipping"
    return 0
  fi
  id="$(perf_ai_feature_id)"
  if [ -n "$id" ]; then
    run_cmd defaults write "$PERF_AI_DOMAIN" "$id" -bool false || return 1
  else
    warn "performance: no Apple Intelligence feature id found in $PERF_AI_DOMAIN — only auto_opt_in is being disabled"
  fi
  run_cmd defaults write "$PERF_AI_DOMAIN" auto_opt_in -bool false
}

perf_ai_ok() {
  local id
  if [ "$(perf_macos_major)" -lt 15 ]; then return 0; fi
  id="$(perf_ai_feature_id)"
  if [ -n "$id" ]; then pref_is "$PERF_AI_DOMAIN" "$id" 0 || return 1; fi
  pref_is "$PERF_AI_DOMAIN" auto_opt_in 0
}

# ---- Per-user launch agents (Siri, Photos/media analysis) -------------------------

# `launchctl disable` in the gui domain persists across reboots and works with
# SIP on (it writes launchd's per-user disabled list). bootout stops a running
# instance now and errors harmlessly when it is not running.
perf_agent_disabled() {
  launchctl print-disabled "gui/$PERF_UID" 2>/dev/null | grep -q "\"$1\" => disabled"
}

perf_agents_apply() {
  local a
  for a in $PERF_AGENTS; do
    run_cmd launchctl disable "gui/$PERF_UID/$a" || return 1
    run_cmd launchctl bootout "gui/$PERF_UID/$a" 2>/dev/null
  done
  return 0
}

perf_agents_ok() {
  local a
  for a in $PERF_AGENTS; do
    perf_agent_disabled "$a" || return 1
  done
  return 0
}

perf_agents_revert() {
  local a
  for a in $PERF_AGENTS; do
    run_cmd launchctl enable "gui/$PERF_UID/$a"
  done
}

# ---- Preferences: Siri, Handoff, diagnostics ---------------------------------------

perf_prefs_apply() {
  run_cmd defaults write com.apple.assistant.support "Assistant Enabled" -bool false || return 1
  run_cmd defaults write com.apple.Siri StatusMenuVisible -bool false || return 1
  # Handoff is a per-host preference (ByHost plist), hence -currentHost.
  run_cmd defaults -currentHost write "$PERF_HANDOFF_DOMAIN" ActivityAdvertisingAllowed -bool false || return 1
  run_cmd defaults -currentHost write "$PERF_HANDOFF_DOMAIN" ActivityReceivingAllowed -bool false || return 1
  run_cmd sudo defaults write "$PERF_DIAG_PLIST" AutoSubmit -bool false || return 1
  run_cmd sudo defaults write "$PERF_DIAG_PLIST" ThirdPartyDataSubmit -bool false || return 1
  run_cmd defaults write com.apple.CrashReporter DialogType -string none || return 1
  return 0
}

perf_prefs_ok() {
  pref_is com.apple.assistant.support "Assistant Enabled" 0 || return 1
  pref_is com.apple.Siri StatusMenuVisible 0 || return 1
  pref_is -currentHost "$PERF_HANDOFF_DOMAIN" ActivityAdvertisingAllowed 0 || return 1
  pref_is -currentHost "$PERF_HANDOFF_DOMAIN" ActivityReceivingAllowed 0 || return 1
  pref_is "$PERF_DIAG_PLIST" AutoSubmit 0 || return 1
  pref_is "$PERF_DIAG_PLIST" ThirdPartyDataSubmit 0 || return 1
  pref_is com.apple.CrashReporter DialogType none || return 1
  return 0
}

perf_prefs_revert() {
  run_cmd defaults write com.apple.assistant.support "Assistant Enabled" -bool true
  pref_delete com.apple.Siri StatusMenuVisible
  pref_delete -currentHost "$PERF_HANDOFF_DOMAIN" ActivityAdvertisingAllowed
  pref_delete -currentHost "$PERF_HANDOFF_DOMAIN" ActivityReceivingAllowed
  pref_delete sudo "$PERF_DIAG_PLIST" AutoSubmit
  pref_delete sudo "$PERF_DIAG_PLIST" ThirdPartyDataSubmit
  pref_delete com.apple.CrashReporter DialogType
}

# ---- Tier 2: report only ---------------------------------------------------------

perf_report() {
  local n
  # TRIM: internal SSDs and Thunderbolt/USB4 NVMe enclosures negotiate it
  # under APFS; USB enclosures never get it on macOS and `trimforce` does not
  # change that, so nothing is forced here.
  # system_profiler lists "TRIM Support:" before "Model:" for NVMe and after
  # it for SATA, so buffer both and print once a pair is complete.
  system_profiler SPNVMeDataType SPSerialATADataType 2>/dev/null \
    | awk '/Model:/ { sub(/^ +Model: /, ""); m = $0 }
           /TRIM Support:/ { sub(/^ +/, ""); t = $0 }
           m != "" && t != "" { print "performance: " m " — " t; m = ""; t = "" }'
  # The Spotlight privacy list is not scriptable without disabling SIP, so the
  # one big internal exclusion worth having is a manual step.
  n="$(mdfind -onlyin "$HOME/Library/Caches" -count 'kMDItemFSName == "*"' 2>/dev/null)"
  if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
    log "performance: Spotlight has indexed $n items under ~/Library/Caches — exclude it once by hand: System Settings > Siri & Spotlight > Spotlight Privacy… (Search Privacy… on macOS 15+) > + > Cmd-Shift-G > ~/Library/Caches"
  fi
  log "performance: Siri Suggestions in Spotlight are a manual toggle: System Settings > Siri & Spotlight > Spotlight > uncheck 'Siri Suggestions'"
  case "$(tmutil destinationinfo 2>&1)" in
    *"No destinations"*) ;;
    *) log "performance: Time Machine is configured — local snapshots keep accruing while automatic backups are on (list: tmutil listlocalsnapshots /)" ;;
  esac
}

# ---- Contract ------------------------------------------------------------------

performance_install() {
  log "performance: applying settings (admin password may be asked)"
  perf_power_apply || return 1
  perf_spotlight_externals off
  perf_ai_apply || return 1
  perf_agents_apply || return 1
  perf_prefs_apply || return 1
  perf_report
  return 0
}

# Re-applying is the drift correction; every command above is idempotent.
performance_update() { performance_install; }

performance_installed() {
  perf_power_ok && perf_spotlight_ok && perf_ai_ok && perf_agents_ok && perf_prefs_ok
}

performance_uninstall() {
  if [ "${1:-keep}" != zap ]; then
    log "performance: settings kept (choose zap to restore macOS defaults)"
    return 0
  fi
  perf_power_revert
  perf_spotlight_externals on
  if [ "$(perf_macos_major)" -ge 15 ] && defaults read "$PERF_AI_DOMAIN" >/dev/null 2>&1; then
    # Removing the domain lets macOS re-apply its default (opt-in) on next boot.
    run_cmd defaults delete "$PERF_AI_DOMAIN"
  fi
  perf_agents_revert
  perf_prefs_revert
  return 0
}
