# 0003 — Defaults are re-seeded by version

Status: accepted.

## Context

Built-in base presets and rules ship as an asset, but the user can delete them,
rename them and switch them on. A new app version may add, reorder or remove
defaults. Keeping user state and updating the bundle are in tension.

## Decision

The bundle carries `defaultsVersion`, stored with the range. A bump re-seeds the
built-in presets and materializes the built-in rules:

- a default the user deleted comes back, switched off;
- a default removed from the bundle, and its activation state, is pruned;
- user-created rules and presets are never touched;
- an active or renamed default keeps its state.

## Consequences

- Every install converges on the same known-good default set.
- Deleting a default is not permanent across a bump. That is the accepted cost;
  a per-item tombstone would be a second source of truth (`VisibleRangeStore`
  comment).
- Built-in rule ids are derived from the bundle id and must never be renumbered,
  or a renamed default would fork into two rules.

## Amendment (2026-11-23)

The pruning half is superseded by
[`0005-visibility-groups.md`](0005-visibility-groups.md): built-in **groups** are
re-added when missing but never pruned, because a group may carry user-authored
conditions; only stale built-in rules in the outside pool are pruned. The
"deleting a default is not permanent" consequence therefore no longer holds for
groups.
