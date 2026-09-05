# macOS Hardening & Performance Design

**Status: implemented 2026-09-05** as two units, `apps/hardening.sh` and
`apps/performance.sh`. Research and v1 scope were written 2026-09-04; the
2026-09-05 revision dropped "Remote Login (SSH) OFF", added the performance
unit, and recorded what the implementation changed. Re-verify commands against
the current macOS release when a new major version ships — the settings below
were checked on Sonoma 14.8 (Apple silicon) and against the Tahoe benchmarks.

## Goal

Manage OS settings as units of this bootstrap — not apps, but sets of settings
that are applied on selection, re-applied (drift correction) on every
`update.sh` run, and reverted on deselection with `zap`:

- **hardening** — a security baseline for a developer machine.
- **performance** — keep the machine and its external disks awake on AC power,
  stop Spotlight indexing external volumes, and switch off features that burn
  CPU, memory and disk in the background.

They are separate so either can be taken alone. Both sit in the "System Tools"
category next to Little Snitch and Control D.

## Fit with the existing engine

The engine's unit contract (`apps/<id>.sh` defining
`<id>_install/_update/_uninstall/_installed`, discovered by glob) maps cleanly:

| Contract fn | Settings-unit semantics |
|---|---|
| `<id>_install` | apply all Tier 1 settings (idempotent) |
| `<id>_update` | re-apply — free drift correction via `update.sh` |
| `<id>_installed` | compliance check: 0 only if every Tier 1 setting holds |
| `<id>_uninstall` | `zap` restores macOS defaults; `keep` leaves the settings |

Tier 2 (report-only) items warn but never gate `_installed`, otherwise a
machine that can't be auto-fixed (e.g. FileVault off) would be re-"installed"
forever.

Both units need `sudo` (precedent: the Xcode unit). All mutations go through
`run_cmd` so `--dry-run` prints the full plan, and the one report check that
needs root (SSH password auth) prints what it would do under `--dry-run`
instead of prompting. bash-3.2-safe and shellcheck-clean like the rest of
`apps/`.

The one engine addition is two helpers in `lib/drivers.sh`: `pref_is` (compare
a `defaults` value, with `-currentHost` support for ByHost domains) and
`pref_delete` (remove a key only when present, optionally via `sudo`). Reverting
a setting therefore never fails on an already-clean machine.

## Research findings

### Security (2026-09-04)

- The CIS Apple macOS 26 Tahoe Benchmark v1.1.0 is the reference standard;
  the ERNW macOS 26 Tahoe hardening guide documents current scriptable
  commands for most items.
- Since macOS Sequoia, `spctl` can no longer modify Gatekeeper (enable /
  disable / rule manipulation deprecated) — configuration profiles are the
  only supported management path. `spctl --status` still reports state.
- Application Firewall settings no longer live in
  `/Library/Preferences/com.apple.alf.plist`; the supported scriptable
  interface is `/usr/libexec/ApplicationFirewall/socketfilterfw`.
- Not scriptable from a booted system: SIP and authenticated root (Recovery
  only). Needs user secrets/decisions: FileVault (password + recovery key),
  screen-lock grace period (`sysadminctl -screenLock` prompts for the user
  password on modern macOS).
- Threat context driving the baseline: infostealers (AMOS/Atomic variants via
  malvertising), malicious LaunchAgents/Daemons persistence, adware
  (Adload), Safari zero-click exploits.
- `/etc/pam.d/sudo` includes `sudo_local` on Sonoma+ (verified on 14.8), so
  Touch ID for sudo can live in a file that OS updates do not overwrite.

### Performance (2026-09-05)

- **Disk sleep.** `pmset disksleep 0` is scriptable and idempotent but only
  stops macOS from sending spin-down commands; drives whose firmware has its
  own idle timer still sleep and need the vendor's tool. Apple-silicon Macs
  have been reported to sleep some external drives every ~30 s, which the
  pmset setting does address.
- **TRIM.** `trimforce enable` only affects internal or SATA third-party
  SSDs. External USB enclosures never get TRIM on macOS; Thunderbolt / USB4
  NVMe enclosures negotiate it automatically under APFS. There is no
  authoritative recommendation to force TRIM on APFS externals, so TRIM is a
  report item (`system_profiler` shows `TRIM Support: Yes/No` per disk).
- **Spotlight.** The Search Privacy list is stored in
  `.Spotlight-V100/VolumeConfiguration.plist` and cannot be edited without
  disabling SIP. Scriptable options are `mdutil -i off` per volume and the
  `.noindex` folder-name suffix (the `.metadata_never_index` sentinel no
  longer works). On this host Spotlight had indexed ~68k items under
  `~/Library/Caches`, so that exclusion is worth a manual step.
- **Apple Intelligence.** Enabled by default on Apple silicon from macOS 15.3.
  Disabled per user via `com.apple.CloudSubscriptionFeatures.optIn`, where the
  key is a numeric feature id that changes across OS updates — read it back
  from the domain, never hardcode it. Restart needed. The domain does not
  exist on Sonoma, so the unit gates on macOS ≥ 15.
- **Background agents.** `launchctl disable gui/UID/<label>` works with SIP on
  (it writes launchd's per-user disabled list; several Apple agents were
  already listed there on this host) and persists across reboots. System-domain
  daemons would need SIP off — out of scope.
- **Handoff** is a ByHost preference (`defaults -currentHost` on
  `com.apple.coreservices.useractivityd`).
- **Time Machine local snapshots.** `tmutil disablelocal` was removed in High
  Sierra; snapshots stop only when automatic backups are off. Report only.
- **Not scriptable cleanly:** Siri/Spotlight Suggestions (an `orderedItems`
  array in `com.apple.Spotlight`), the Login Items "Allow in background" list,
  Reduce Motion / Transparency (`com.apple.universalaccess` needs Full Disk
  Access for the calling terminal). Suggestions are printed as a manual step;
  the others are left out.

## Decisions

- **SSH stays on.** The 2026-09-04 draft turned Remote Login off (CIS). These
  machines are administered over SSH, so Remote Login is left however the user
  set it and the unit instead warns when `sshd -T` shows password
  authentication still enabled.
- **Two units, one spec.** Security and performance are independently
  selectable; the engine mapping and tiering rules are shared, so they share
  this document.
- **Spotlight: external volumes only.** No `.noindex` renames — the Dev tree
  lives inside `~/Library/CloudStorage/Dropbox`, and renaming paths there is
  not worth the CPU saved. `~/Library/Caches` exclusion is printed as guidance.
- **Sleep policy: AC never sleeps, battery untouched** except disk sleep. The
  Mac mini stays up for colima and SSH; the MacBook Air keeps its battery life.
- **FileVault warning vs colima.** colima's boot-time start needs FileVault
  off, so the FileVault warning says to skip it on such a machine.

## hardening — scope

### Tier 1 — applied automatically

| Setting | Command |
|---|---|
| Application firewall ON + stealth + logging | `sudo socketfilterfw --setglobalstate on --setstealthmode on --setloggingmode on` |
| Guest login and SMB guest access off | `GuestEnabled false` in `/Library/Preferences/com.apple.loginwindow`; `AllowGuestAccess false` in `/Library/Preferences/SystemConfiguration/com.apple.smb.server` |
| Automatic login disabled | `defaults delete .../com.apple.loginwindow autoLoginUser` (if present) |
| Automatic security updates on, macOS upgrades manual | `AutomaticCheckEnabled`, `AutomaticDownload`, `CriticalUpdateInstall` (security responses / security fixes), `ConfigDataInstall` (system data files) true and `AutomaticallyInstallMacOSUpdates` **false** in `/Library/Preferences/com.apple.SoftwareUpdate`; `AutoUpdate true` in `/Library/Preferences/com.apple.commerce` (App Store apps, not the OS). Corrected 2026-09-05 from "all updates on": OS installs reboot the machine and can break dev toolchains, so they stay a manual decision. |
| Show all filename extensions | `NSGlobalDomain AppleShowAllExtensions true` (blocks `invoice.pdf.app` tricks) |
| Touch ID for sudo | `auth sufficient pam_tid.so` appended to `/etc/pam.d/sudo_local` (never overwritten, so a `pam_reattach` line survives); skipped with a warning when `/etc/pam.d/sudo` has no `sudo_local` include |

Deliberately excluded: CIS's stricter firewall options (`--setblockall on`,
disabling auto-allow of signed software) — constant prompts, break dev
workflows — and Remote Login off (see Decisions).

### Tier 2 — check and warn only

| Check | Why not auto-fix |
|---|---|
| FileVault (`fdesetup status`) | needs user password + recovery-key decision; conflicts with colima boot-start |
| SIP (`csrutil status`) | changeable only from Recovery |
| Gatekeeper (`spctl --status`) | not scriptable since Sequoia; on by default |
| SSH password auth (`systemsetup -getremotelogin`, then `sshd -T`) | the fix is a key-only policy in `/etc/ssh/sshd_config.d/`, which must not lock the user out; skipped under `--dry-run` because it needs sudo |

### Revert (`zap`)

Firewall off/stealth off/logging off; the managed `defaults` keys are deleted
so macOS defaults apply again; the `pam_tid.so` line is removed and
`sudo_local` deleted if nothing but comments remain. Auto-login is not
restored (it was removed, not replaced).

## performance — scope

### Tier 1 — applied automatically

| Area | Setting |
|---|---|
| Power | `pmset -c sleep 0 disksleep 0 powernap 0`; on machines with a battery also `pmset -b disksleep 0`. Nothing else on battery. |
| Spotlight | `mdutil -i off` on every mounted `/Volumes/*` that is a real directory on a different device than `/` (the boot volume's entry is a symlink). Re-run on every update so newly attached drives are covered. |
| Apple Intelligence (macOS ≥ 15) | read the numeric feature id from `com.apple.CloudSubscriptionFeatures.optIn`, write it `false`, plus `auto_opt_in false`. Skipped with a log line on Sonoma. |
| Siri | `com.apple.assistant.support "Assistant Enabled" false`; `com.apple.Siri StatusMenuVisible false`; `launchctl disable gui/UID/com.apple.Siri.agent` + `bootout` |
| Photos/media analysis | `launchctl disable gui/UID/com.apple.photoanalysisd` and `com.apple.mediaanalysisd` + `bootout` (breaks Photos face/scene search only) |
| Handoff | `defaults -currentHost write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed false` and `ActivityReceivingAllowed false` |
| Diagnostics | `AutoSubmit false` and `ThirdPartyDataSubmit false` in `/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist`; `com.apple.CrashReporter DialogType none` |

### Tier 2 — report only

- TRIM support per SSD from `system_profiler SPNVMeDataType SPSerialATADataType`
  (with the USB-vs-Thunderbolt note above); `trimforce` is never run.
- Spotlight tip on every run when `mdfind` finds indexed items under
  `~/Library/Caches`: add it via System Settings > Siri & Spotlight >
  Spotlight Privacy… (Search Privacy… on macOS 15+).
- Siri Suggestions in Spotlight: manual toggle, printed every run.
- Time Machine configured → note that local snapshots accrue while automatic
  backups are on.

### Revert (`zap`)

`pmset -c sleep 1 disksleep 10 powernap 1` and `pmset -b disksleep 10` (Apple
silicon defaults recorded on Sonoma 14.8; `pmset restoredefaults` was rejected
as too broad), `mdutil -i on` on external volumes, `launchctl enable` on the
three agents, the Apple Intelligence domain deleted so the OS default returns,
Siri re-enabled, the remaining managed keys deleted.

## Deferred

Per-setting opt-out granularity; screen-lock grace period (interactive
password); AirDrop / sharing-services audit; password policy (`pwpolicy`);
login banner; no `.DS_Store` on network/USB volumes; Remote Management (ARD)
deactivation via `kickstart`; Lockdown Mode; Reduce Motion / Transparency
(needs Full Disk Access for the terminal); Login Items "Allow in background"
pruning (no stable CLI); `.noindex` folder exclusions (renames paths).

## Files

- `apps/hardening.sh`, `apps/performance.sh` — the units
- `lib/drivers.sh` — `pref_is`, `pref_delete`
- `README.md` — managed-apps table rows; `docs/howto.md` — operating notes
  (manual steps, verification commands, SSH key-only policy)
- This spec

Verification: `bash -n` + shellcheck on the three shell files, then
`./run.sh --dry-run --apps hardening,performance` to review the printed plan,
then apply on one machine and confirm with `pmset -g custom`, `mdutil -s -a`,
`launchctl print-disabled gui/$(id -u)`, and
`/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`.

## Sources

- [CIS Apple macOS Benchmarks](https://www.cisecurity.org/benchmark/apple_os)
- [ERNW Hardening Guide — macOS 26 Tahoe](https://github.com/ernw/hardening/blob/master/operating_system/osx/26/Hardening_Guide-macOS_26_Tahoe_1.0.md)
- [macOS Sequoia spctl/Gatekeeper deprecation](https://www.linkedin.com/pulse/macos-sequoia-gatekeeper-deprecation-spctl-what-means-security-fp4ac)
- [What's new for enterprise in macOS Sequoia (Apple)](https://support.apple.com/en-us/121011)
- [Addigy: macOS 26 Tahoe compliance benchmarks](https://addigy.com/blog/macos-26-tahoe-compliance-benchmarks/)
- [macos-defaults: Toggle Apple Intelligence](https://macos-defaults.com/misc/apple-intelligence.html)
- [Eclectic Light: Should you trim external SSDs?](https://eclecticlight.co/2023/03/25/should-you-trim-external-ssds/)
- [Eclectic Light: Which external drives have Trim and SMART support?](https://eclecticlight.co/2024/04/09/which-external-drives-have-trim-and-smart-support/)
- [Eclectic Light: Using and troubleshooting Spotlight in Sequoia](https://eclecticlight.co/2024/11/29/using-and-troubleshooting-spotlight-in-sequoia-summary/)
- [Apple: About Time Machine local snapshots](https://support.apple.com/en-us/102154)
- [Macworld: How to stop a Mac's hard drives from spinning down](https://www.macworld.com/article/2564987/how-to-stop-a-macs-hard-drives-from-spinning-down.html)
- [AppleInsider: How to stop mediaanalysisd from hogging your CPU](https://appleinsider.com/inside/macos-ventura/tips/how-to-stop-mediaanalysisd-from-hogging-your-cpu-in-macos)
