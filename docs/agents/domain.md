# Domain Docs

How skills consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root: the glossary.
- **`docs/adr/`**: the ADRs that touch the area you're about to work in.

This is a single-context repo: one glossary and one ADR folder, both at the root. Either may be absent. The `/domain-modeling` skill (also reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily, the moment a term or decision is actually resolved. Treat absence as "nothing recorded yet" and proceed silently.

## Use the glossary's vocabulary

When your output names a domain concept (an issue title, a refactor proposal, a hypothesis, a test name), use the term as `CONTEXT.md` defines it, including where it explicitly rejects a synonym.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
