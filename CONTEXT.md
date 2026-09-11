# claude-mac-bootstrap

The vocabulary of a repo that describes a desired macOS machine and converges real machines onto it. Each machine clones the repo and runs the automation locally; the repo holds the desired state, the machine holds what was chosen for it.

## Language

### Units and selection

**Unit**:
One selectable thing the automation manages, defined by a single script. Most units are apps, but a unit can also be a set of macOS settings or a roster of agent add-ons.
_Avoid_: app script, package, module, recipe

**App**:
A unit whose subject is an application or command-line tool installed on the machine.
_Avoid_: program, cask (that is one driver, not the app)

**Settings unit**:
A unit whose subject is a set of macOS settings rather than an application. It is "installed" while every setting it applies is in place. Hardening and performance tuning are settings units.
_Avoid_: profile, tweak script

**Unit id**:
The short name a unit is selected by, such as `chrome` or `claude-code`. It is the unit's identity everywhere: the checklist, the saved selection, and command-line flags.
_Avoid_: app name (that is the display name), slug

**Category**:
The checklist grouping a unit is shown under, such as Browsers, AI, or System Tools.

**Selection**:
The set of unit ids a machine has chosen to manage. It is machine-local, never in the repo, and doubles as the record of what is currently managed on that machine.
_Avoid_: config, profile, machine config, app list

**Saved selection**:
The selection recorded by the previous run on this machine. Reconciliation diffs it against the new selection.

**Reconcile**:
The pass that converges a machine on its new selection: newly selected units are installed, still-selected units are updated, and deselected units are removed.
_Avoid_: sync, apply, provision

**Bootstrap**:
The first run on a fresh machine, from one command with no prerequisites: it installs Homebrew, places the managed files, then reconciles the first selection.
_Avoid_: setup, provisioning, onboarding

**Update run**:
A run that updates every unit in the saved selection without changing it. It fetches the latest automation first and never prompts.
_Avoid_: upgrade, refresh

**Note**:
The unit's post-install guidance for steps only a human can do, such as a licence, a sign-in, or a system-extension approval. Printed in the run summary.
_Avoid_: caveat, warning, hint

### Drivers and removal

**Driver**:
A shared install strategy a unit delegates to: Homebrew cask, Homebrew formula, vendor dmg, native installer, Mac App Store, VS Code extension, or a preference write. A unit picks a driver; anything vendor-specific stays in the unit.
_Avoid_: installer, backend, method, source

**Vendor dmg**:
A driver that installs an app straight from the vendor's download rather than through a cask, used where the cask trails releases or was dropped.
_Avoid_: direct download, manual install

**Self-updating app**:
An app whose own updater keeps it current once installed, so an update run only reinstalls it when it is missing.
_Avoid_: auto-update cask

**Adopt**:
Take over an app the user installed by hand so its unit manages it from then on, without reinstalling it.
_Avoid_: import, claim

**Keep**:
The removal mode that uninstalls a deselected unit's app and leaves its settings and data in place. The default, and the only mode a non-interactive run uses.
_Avoid_: soft uninstall, remove only

**Zap**:
The removal mode that uninstalls a deselected unit's app and its settings and data too. For a settings unit, zap restores the macOS defaults.
_Avoid_: purge, clean uninstall, wipe

**Drift correction**:
What updating a settings unit does: re-apply every setting in its baseline, so a value changed by hand or by macOS goes back.
_Avoid_: enforcement, re-sync

**Reported setting**:
A setting a settings unit checks and shows but never changes, because changing it needs Recovery, a user secret, or a configuration profile. FileVault and SIP are reported settings.
_Avoid_: read-only setting, tier 2

### Rosters and state

**Roster**:
The repo-side list of what a unit manages, such as the skill repos, the MCP servers, or the Claude Code plugins. The roster is the desired set; a machine's selection or saved choices narrow it.
_Avoid_: manifest, inventory, list, catalogue

**Roster record**:
One line of a roster, describing one managed thing. Records follow the roster's own field format.
_Avoid_: entry, row

**State file**:
The machine-local record of what a unit itself applied on this machine. Only things in the state file are ever removed, so anything the user added by other means is left alone.
_Avoid_: cache, lock file (the skills unit reads the CLI's lock file for this role), ledger

**Name clash**:
A roster name that already exists on an agent but is not in the state file. The unit logs it and leaves it alone rather than taking it over.
_Avoid_: conflict, collision, duplicate

**Track all**:
A saved skill choice of `*` for a repo: follow the whole upstream repo, so skills added upstream arrive on the next update and removed ones are cleaned out.
_Avoid_: wildcard, follow upstream, everything

### Agents and their add-ons

**Agent**:
An AI coding CLI the units configure: Claude Code, Codex, or Gemini CLI. An agent that is not installed yet is skipped and picked up on a later run.
_Avoid_: tool, assistant, AI CLI, model

**Skill**:
A standalone instruction package installed from an upstream repo into the shared store and linked into each agent.
_Avoid_: prompt, command, recipe

**Suite**:
A workflow skill repo managed as a whole, such as superpowers or mattpocock/skills. Suites have their own unit so they can be selected independently of individual skills.
_Avoid_: bundle, kit, pack

**Shared store**:
The single place on the machine where installed skills live, from which every agent reads or links.
_Avoid_: skills dir, global skills

**Plugin**:
A Claude Code plugin installed from a marketplace. A plugin can carry hooks; a skill cannot, which is why some suites ship as both.
_Avoid_: extension, add-on

**Marketplace**:
A registered source Claude Code plugins are installed from.
_Avoid_: registry, feed

**MCP server**:
A tool server applied to every installed agent from the MCP roster, by name and transport.
_Avoid_: MCP, tool server, integration

### Machine and repo

**Managed file**:
A repo file the automation places on the machine, as a symlink or a copy. The repo copy is authoritative; local edits are overwritten on the next run.
_Avoid_: dotfile (some managed files are not dotfiles), config file

**Machine-local state**:
Everything the automation records about one machine: the selection, saved choices, and state files. Lives outside the repo, so a checkout can be moved or re-cloned freely.
_Avoid_: local config, repo config, host config

**Sweep**:
The daily pass that marks every git directory and every rebuildable build or dependency directory under Dropbox as ignored by Dropbox sync, so sync can never corrupt a git index or churn on generated trees.
_Avoid_: cron job, cleanup

### Claude Code payload

**Per-turn payload**:
Everything Claude Code sends the model on every turn that the user never sees: tool schemas, the skills catalogue, and feature instructions.
_Avoid_: system prompt bloat, context overhead, hidden context

**Lean profile**:
The managed Claude Code settings tuned to keep the per-turn payload small: denied tools, disabled features, and user-invocable-only skills.
_Avoid_: minimal config, trimmed settings

**Context audit**:
A measured probe of the per-turn payload, recorded against previous runs so growth is visible. Never run unattended; each probe costs one API request.
_Avoid_: token check, prompt audit
