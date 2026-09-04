# macOS Hardening Design (proposed, not implemented)

**Status: research + proposed v1 scope only. No code exists yet.** Written
2026-09-04 to be picked up later. When implementing, re-verify commands
against the current macOS release first.

## Goal

Add OS hardening as a managed unit of this bootstrap — not an app, but a set
of security settings that are applied on selection, re-applied (drift
correction) on every `update.sh` run, and reverted on deselection.

## Fit with the existing engine

No engine changes needed. The engine's unit contract
(`apps/<id>.sh` defining `<id>_install/_update/_uninstall/_installed`,
discovered by glob) maps cleanly:

| Contract fn | Hardening semantics |
|---|---|
| `hardening_install` | apply all Tier 1 settings (idempotent) |
| `hardening_update` | re-apply — free drift correction via `update.sh` |
| `hardening_installed` | compliance check: 0 only if every Tier 1 setting holds |
| `hardening_uninstall` | `zap` reverts managed settings to macOS defaults; `keep` leaves them |

Tier 2 (report-only) items warn but never gate `hardening_installed`,
otherwise a machine that can't be auto-fixed (e.g. FileVault off) would be
re-"installed" forever.

Unit needs `sudo` (precedent: the Xcode unit). All mutations go through
`run_cmd` so `--dry-run` prints the full plan. Must stay bash-3.2-safe and
shellcheck-clean like the rest of `apps/`.

## Research findings (2026)

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

## Proposed v1 scope

### Tier 1 — applied automatically (scriptable, idempotent, dev-machine safe)

| Setting | Command sketch |
|---|---|
| Application firewall ON + stealth + logging | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on --setstealthmode on --setloggingmode on` |
| Guest account disabled (login + SMB) | `sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false`; SMB guest access off (`com.apple.AppleFileServer` / `com.apple.smb.server` guest keys) |
| Automatic login disabled | `sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser` (if present) |
| All automatic software updates ON | `sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate` keys `AutomaticCheckEnabled`, `AutomaticDownload`, `AutomaticallyInstallMacOSUpdates`, `CriticalUpdateInstall`, `ConfigDataInstall` `-int 1`; plus `/Library/Preferences/com.apple.commerce AutoUpdate -int 1` |
| Remote Login (SSH) OFF | `sudo systemsetup -f -setremotelogin off` |
| Show all filename extensions | `defaults write NSGlobalDomain AppleShowAllExtensions -bool true` (blocks `invoice.pdf.app` double-extension tricks) |
| Touch ID for sudo | `/etc/pam.d/sudo_local` with `auth sufficient pam_tid.so` (survives OS updates on Sonoma+) |

Deliberately excluded from Tier 1: CIS's stricter firewall options
(`--setblockall on`, disabling auto-allow of signed software) — they cause
constant prompts and break dev workflows.

### Tier 2 — check and warn only

| Check | Why not auto-fix |
|---|---|
| FileVault (`fdesetup status`) | needs user password + recovery-key decision; warn with instructions |
| SIP (`csrutil status`) | changeable only from Recovery |
| Gatekeeper (`spctl --status`) | not scriptable since Sequoia; on by default — warn if off |

### Deferred to v2+

Per-setting opt-out granularity; screen-lock grace period (interactive
password); AirDrop / sharing-services audit; password policy (`pwpolicy`);
Wake-on-LAN + Power Nap off; login banner; no `.DS_Store` on network/USB
volumes; Remote Management (ARD) deactivation via `kickstart`; Lockdown Mode.

## Files to touch when implementing

- `apps/hardening.sh` — new unit (id `hardening`, `APP_NAME="macOS Hardening"`,
  `APP_NOTE` covering sudo requirement + FileVault manual step)
- `README.md` — managed-apps table row
- This spec — update from "proposed" to implemented, adjust for anything that
  changed during implementation

Verification plan: `sh -n` + shellcheck, then
`./run.sh --dry-run --apps hardening` to review the printed command plan
before ever applying to a real machine.

## Sources

- [CIS Apple macOS Benchmarks](https://www.cisecurity.org/benchmark/apple_os)
- [ERNW Hardening Guide — macOS 26 Tahoe](https://github.com/ernw/hardening/blob/master/operating_system/osx/26/Hardening_Guide-macOS_26_Tahoe_1.0.md)
- [macOS Sequoia spctl/Gatekeeper deprecation](https://www.linkedin.com/pulse/macos-sequoia-gatekeeper-deprecation-spctl-what-means-security-fp4ac)
- [What's new for enterprise in macOS Sequoia (Apple)](https://support.apple.com/en-us/121011)
- [Addigy: macOS 26 Tahoe compliance benchmarks](https://addigy.com/blog/macos-26-tahoe-compliance-benchmarks/)
