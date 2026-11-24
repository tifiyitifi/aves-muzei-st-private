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

## Visibility groups: three tiers, one formula

A gallery scope stores N mutually exclusive groups plus one `outside` row; a
wallpaper group stores exactly one group. Every condition is a rule with one of
three roles: `source` (OR between rules, AND inside a rule), `restriction` (AND)
and `supplement` (OR).

`resolve()` evaluates the group with its own order, then applies the outside pool
last:

```
group   = (sources AND restrictions) OR supplements        // or the union-first variant
browsing = (group AND outsideRestrictions) OR outsideSupplements
```

The exclusive/multi-select difference is not a second model: it is a guard on the
enable toggle. The gallery enables exactly one source per group; wallpaper groups
mark conditions per surface. `WallpaperConditionSurfaces` is the only place that
knows Home is `1` and Lock is `2`.

The gallery lock therefore freezes the scope, not one row: switching groups,
creating groups, editing any condition and editing the outside pool all ask the
same gate. The wallpaper group lock hides the other groups and freezes every
group, the locked one included.

## Pinning is a split, not a dump

A pinned media set is split with `splitVisibleRangePin`: a source-only union
becomes one source per member, every other positive source stays one conjunctive
source, and the rest becomes restrictions. A reversed filter or a mixed union
stays a restriction, because turning it into a positive source would invert its
meaning. Forced roles are an explicit semantic change and are not promised to be
equivalent to the media set. The outside pool has no attributes: its two targets
put every filter in their own role.

The first pin into a group enables its conditions; later pins park them, so a
second visit never silently changes what browsing shows. Re-pinning an existing
condition keeps its state.

## The save sheet folds the rules, not their destination

`Injection options` is the one collapsible block: injection mode, the remember
option, role, append/replace and the write-back rule list all live inside it.
Only the injection mode is stored; the caption says so explicitly, and clearing
the option rewrites the stored mode to `auto` so the switch cannot disagree with
the next open. Role is a two-button control — a direct automatic split and a
menu button that asks on every tap — and is never persisted. Append and replace
are named buttons because a switch labelled 「Append」 does not say what the off
state means. The save writes in two places, so the list outside the fold names
both: the checked groups (pins) first, then the checked write-back rules. A
forced role is named on a group pin because it is known at save time; an
automatic split is not, so only the owner is named. A wallpaper pin is prefixed
with its section so it cannot be confused with a same-numbered gallery group.

The sheet opens with nothing checked. The two selections are separate: pin
targets are ordinary `setState` state because a tile must repaint, while the
rule selection is a single `ValueNotifier<Set<String>>`. The folded row list and
the summary outside it are the only listeners, so ticking a rule repaints those
two subtrees and the save button — the grids, chips and text fields never
rebuild for it. Everything in the summary is derived from the same ids the
confirmation passes to `pinFilters` and `writeBackTargets`.

## The page lists groups; a group's conditions live in its editor

The gallery page is a four-part selection surface: the **groups** (exclusive),
the **outside restrictions**, the **outside supplements**, and the **currently
visible** result. A group tile previews the group's browsed result — its own
conditions joined with the outside pool — so the cover and count say what
switching to it would show. The tile is a selector: its long press enters the
selection, and the overflow offers the group actions; it never appends filters
to the media set.

Group 0 is the **「Unrestricted」 sentinel**: always present, always empty, always
first, never a save target, never numbered as a data group (the data groups are
`1..n`, like the wallpaper page's group 0 = "no group"). The controller refuses
condition writes to it in one guard (`isGroupZero`), and the seeder/init clears a
legacy condition so a migrated base cannot linger.

A group's own **base range / restrictions / supplements** are edited on
`VisibleRangeGroupEditorPage`, reached from the group's overflow action. The page
works on a draft, exactly like the wallpaper group page: every switch edits the
draft, closing asks to save or discard, and only the save writes the aggregate.
It has no surface axis, because the gallery has one surface.

The save action is named **「save to visible range」** and writes immediately; it
is distinct from the filter pin, which the user may mean when they say "pin".

## The bar places both fork pages on one side

The wallpaper page and the group editor are peers of the range entry. Their
entries are derived, never written into the user's list: the configured side
(`GroupedWallpaperNavMode`) decides left or right, and their open ticks decide
the order — the first opened sits nearest the range entry. In the shared mode
neither entry exists; the single shell entry flips between the range page, the
wallpaper page and the editor, and a closed editor session falls back to the
range page. In a separate mode the editor is pushed over the page it was opened
from (the range page included), so closing it returns there and a process death
restores the range page: the edited group is session state, not a stored
destination.

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
- **Offering group 0 as a save target or letting a condition into it.** The
  sentinel stops meaning 「Unrestricted」 the moment it can carry a filter.
- **Writing the editor draft on every tap.** The page is an aggregate; a
  half-applied group is what the discard action must be able to undo.
- **Treating a base as one on/off unit.** The base is a union: each source is an
  OR member and is switched on its own. Widget-level code must not clear or set
  the whole set for a single tile (`POOL-1`).
- **Deleting a source when the user picks 「Unrestricted」.** Park it instead: a
  source carries the user's filter, and 「Unrestricted」 is the absence of an
  *active* source, not of a stored one (`GRP-9`).
- **Adding a fork route without an `AvesNavItem` page builder.** `routeBuilder`
  resolves the page eagerly, so a missing case throws `unknown route` and the bar
  entry looks dead while the page itself is fine (`NAV-8`).
- **Writing the remembered flag only when the switch is checked.** An unchecked
  switch then leaves the old mode stored and silently restores it (`SAVE-3`).
- **Folding away the write destination with the rule list.** The list is an
  advanced edit; the location it will overwrite is not (`SAVE-6`).
- **Preselecting the current group.** A save is an explicit act; beginning with a
  tick silently assigns the group the user happens to be viewing (`SAVE-7`).
- **Refreshing the summary by re-reading the store or rebuilding the sheet.**
  Both selections are live in memory; a tap only notifies the readers of that
  one value (`SAVE-6`).
- **Calling the gallery groups just 「Groups」 next to 「Wallpaper groups」.**
  The two sections write different scopes (`SAVE-8`).
