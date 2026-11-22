# Visible range — design

## One expression, three readers

```
VisibleRange (base + rules + order)
        │ resolve()
        ▼
   CollectionFilter?
        │
        ├──► paged predicate (collection_paging)
        ├──► summary exclusion (counts, covers, album lists)
        └──► legacy in-memory scan
```

`VisibleRangeGate` is the only seam the three browsing paths ask. Each path used
to decide for itself whether a range applied, which is how a range could restrict
the grid and not the counts (or the reverse). The gate also hands out the
complement (`summaryExclusion`) so summary queries model the same set as
"entries to exclude" instead of re-deriving the range.

The trash filter is exempt: the recycle bin is a management surface, and its
contents must stay visible to restore or empty them.

## The expression, not a saved list

A range stores a base filter set, restriction rules (AND), supplement rules (OR)
and an order. `resolve()` builds one `CollectionFilter` tree:

- `intersectFirst`: `(base AND restrictions) OR supplements` — a supplement can
  reach outside the base, which the page labels 「范围外补充」.
- `unionFirst`: `(base OR supplements) AND restrictions` — supplements are then
  narrowed by the restrictions, 「限制外补充」.

Both are built from the same pieces, so an unrestricted base collapses to no-op
in either order. `resolvedIntermediate` mirrors the exact first half of
`resolve()`: the page shows a cumulative count after that step, and a different
tree would show a count that does not match the result.

`isRestricted` deliberately ignores supplements: a supplement can only add
entries the base already allowed when the base is unrestricted, so it can never
make browsing narrower.

## Two scopes, one table

Every range row is qualified by `(scope, ownerId)`. The gallery keeps one range
with the fixed ids `gallery/gallery`; a wallpaper group owns a row under its
group id. Store reads take both values, so a group range can never leak into the
gallery. Rule ids are globally unique and are used for applied-target bookkeeping.

## Defaults are data, re-seeded by version

Built-in base presets and rules come from `assets/visible_range_presets.json`.
`defaultsVersion` is stored next to the range. A bump re-seeds the set:

- defaults the user deleted come back;
- defaults removed from the bundle, and their activation state, are pruned;
- user rules and presets are untouched;
- an active or renamed default keeps its state.

A per-item tombstone would preserve deletions, at the cost of a second source of
truth (see `0003`). Restriction and supplement defaults are materialized switched
off, because they are candidates, not a decision.

## The wallpaper page overlays, it does not replace

The wallpaper page's group range is browsing state, not a second gallery range:

- `claimWallpaperScope` returns a per-page token; `publish` and `release` only
  apply for the current token. Value equality is not enough: a replacement page
  often publishes the same group, and an older page closing must not clear it.
- `gallerySuspended` is a temporary view choice; dropping the overlay restores
  the gallery range, and nothing is written.
- The overlay is in-memory. A process restart returns to the gallery range alone.
- The live wallpaper never reads the gate; it resolves its saved group range
  directly, so gallery browsing can never narrow the wallpaper.

Releasing is deferred to a microtask: closing a page can run while the framework
is finishing a route transition, where notifying listeners would throw.

## The lock is a permission preset, not a password

A locked range freezes a set of operations for the browsing session. The three
presets are data (`readOnly`, `manageable`, `full`); `allows()` maps each library
mutation to the permission it needs, and returns true immediately for an unlocked
range, so callers need no separate check. The lock is casual protection inside
Aves and is documented as such in the UI.

## Anti-patterns

- **Reading `visibleRangeController.gallery.resolve()` directly in a browsing
  path.** Ask the gate, or the wallpaper overlay is silently ignored.
- **Deriving the summary exclusion by re-filtering in memory.** Use
  `summaryExclusion`, or counts and grid disagree.
- **Writing `gallerySuspended` into the saved range.** Suspension is a view
  choice; persisting it would make leaving the page destructive.
- **Comparing overlay values to decide ownership.** Use the page token.
- **Adding a default preset by editing the JSON without bumping
  `defaultsVersion`.** Existing installs would never see it.
