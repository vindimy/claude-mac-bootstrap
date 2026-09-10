# claude-mac-bootstrap

Bash automation that bootstraps a macOS machine and keeps its apps, tools, and configs in a desired state. `run.sh` installs the per-app units in `apps/`; the shared engine lives in `lib/`.

## Constraints

- Every script runs on stock macOS bash 3.2 (`/bin/bash`, never Homebrew bash) and passes shellcheck.
- Test gate: `tests/run.sh` (shellcheck plus every `tests/test_*.sh`, offline, under `/bin/bash`). Run it before reporting a change as working; a behaviour change lands with a test.
- The repo holds automation only, never a machine's configuration. Machine-local state lives under `~/.mac-bootstrap/`.
- A change to a unit or a managed file also updates its row in `README.md` and its section in `docs/howto.md`.

## Agent skills

### Issue tracker

GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` plus `docs/adr/`, created lazily by `/domain-modeling`. See `docs/agents/domain.md`.
