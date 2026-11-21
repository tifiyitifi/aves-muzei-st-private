# 0003 — The slice README stays the mechanism doc until the register is stable

Date: 2026-11-21

## Context

`lib/features/grouped_wallpaper/README.md` is a long mechanism narrative built
across dozens of fixes. `docs/README.md` asks for a feature to keep its spec,
design, rules, recurrences and decisions under `docs/features/<feature>/`.

Moving the narrative while the feature is still being fixed would mix a large,
lossy rewrite with a behaviour change, and the register is the part the next
change needs first.

## Decision

For now:

- `docs/features/grouped_wallpaper/` owns the requirements, the case register,
  the recurrences, the testing gates and the decisions.
- `design.md` states the invariants those documents rely on and links to the
  slice README for the full narrative.

When the register is stable, the narrative moves into `design.md` with
`git mv` so its history follows, and the slice file becomes a short pointer.

## Consequences

- Two files can mention the same mechanism; the rule is that only one states it.
  The register states the invariants; the slice README states the narrative.
- The migration is tracked in `tasks.md` and is not a precondition for a fix.
