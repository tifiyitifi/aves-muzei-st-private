# Search filters (assist) — design

## The value

`SearchAssist` is an immutable `Equatable` value with `with*`/`without`/`clearOther`
and a `const empty`. The sheets never mutate it: they hand a new copy back, or
`null` when dismissed. The search delegate owns the single
`ValueNotifier<SearchAssist>`, so nothing is persisted and nothing leaks between
search sessions.

`hasOther` deliberately excludes the path condition: the section shows two chips
("Path" and "More filters") and they must light independently.

The filter count is a field count, not a bound count: `AssistIntRange.toFilter`
returns `null` when both bounds are absent, so an empty range disappears rather
than becoming a match-all. A dimension adds two filters but one chip, so removing
the chip cannot leave half a condition behind.

## The two filter types

```text
relative_time   span (3h/7d) + optional reversed
assist_range    field (takenDate|size|width|height|contentId) + bounds + optional reversed
```

Both implement the app's `CollectionFilter` contract, so they round-trip through
JSON, take part in filter equality, and reach the SQL seam through the shared
`WindowFragment` contract in `collection_filter_sql.dart`.

`RelativeTimeFilter` anchors `cutoffMillis` once, at construction, and persists
only the span. Equality ignores the anchor, so a restored filter dedupes against
the one it came from. A reversal keeps that cutoff and flips only the condition:
a visible range browses with the positive filter and excludes with its reversal,
so two anchors would stop the two sides partitioning the library.

`RangeAssistFilter` reads, per field:

| Field | Value |
| --- | --- |
| `takenDate` | `AvesEntry.bestDate` |
| `size` | `sizeBytes ?? 0` |
| `width`/`height` | `displaySize` (rotation-swapped) |
| `contentId` | the content id, absent for some rows |

## SQL parity

The SQL fragment mirrors each Dart test, including the NULL behaviour: a reversed
range compiles to `COALESCE((fragment), 0) = 0`, which keeps the rows whose field
is absent exactly as `!test` does. The relative window interpolates the filter's
cutoff, never the clock, so a paged window and an in-memory browse cannot disagree
about where the window starts.

Width and height swap their comparison sides when the rotation is a quarter turn,
using the catalogue rotation with the source rotation as a fallback.

## Extensions

Extensions are not a new filter type: one extension becomes
`QueryFilter('EXT=<ext>')`, several become a `SetOrFilter` over the same queries.
The app's query compiler keeps owning extension matching, and upstream's filter
factory does not gain a case.

## The sheets

- **Path** — a folder browser over the platform's storage volumes; an unreadable
  directory reads as "nothing below here". The mode is two choice chips
  (include/exclude), not a segmented button, because the labels are long.
- **More filters** — six tabs: date, size, dimensions, format, content id,
  recently added. Date presets and the custom range are computed in the sheet as
  local-day epoch bounds; the size arithmetic lives in `size_assist_unit.dart`
  (unit conversion, exact-unit choice and formatting), so both fields keep the byte
  value and a positive bound never rounds to zero; the label comes from the
  localization. Done is disabled while the lower bound exceeds the upper.
- The match count is advisory and describes what the grid shows: the visible
  range, hidden albums, locked vaults and the stack filter all apply, so a stack
  counts once. Any doubt (empty set, inexpressible filter, unready store) reports
  `null` and the sheet omits the number. `CountDebouncer` coalesces edits and
  ignores an answer that arrives after a newer draft or a closed sheet.

## Anti-patterns

- Persisting the resolved instant of a relative window: a saved search must keep
  meaning "the last N".
- Adding a filter type for extensions: the query language already has `EXT`.
- Letting an empty range match everything: an empty condition must vanish.
- Comparing a relative filter by its anchor: two identical conditions would stop
  deduping.
- Treating the match count as the view's total: it does not apply the stack filter
  or the locked vaults.
