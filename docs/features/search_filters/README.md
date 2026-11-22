# Search filters (assist)

A structured condition builder on the collection search page: a directory, date,
size, width/height and content-id ranges, a "last N hours/days" window and a set of
extensions, applied as ordinary `CollectionFilter`s on top of the typed query.

Status: **in progress**. The models, the sheets, the SQL fragments and the section
are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- the `TIME2NOW` token (`3h`, `7d`) as the persisted form of a relative window;
- `RelativeTimeFilter` and `RangeAssistFilter` (date, size, width, height, content
  id) as first-class filters with JSON round-trip;
- `SearchAssist`, the immutable value the sheets edit and the section renders;
- SQL parity for the two filter types, so a paged browse and a legacy browse
  select the same entries;
- the two sheets (path and "more filters") and the assist section.

Out of scope:

- a new free-form query language: extensions reuse the app's own `EXT=` query;
- persisting the assist between search sessions (the applied filters are what is
  remembered, in the collection and in search history);
- the user's own visible-range presets, which merely reuse `RelativeTimeFilter`.

## Version facts

| Fact | Value |
| --- | --- |
| Token | `<amount><h\|d>` (hours or days, positive) |
| Relative type | `relative_time` (`type` + `span` + optional `reversed`) |
| Range type | `assist_range` (`field` + bounds + optional `reversed`) |
| Range fields | `takenDate`, `size`, `width`, `height`, `contentId` |
| Extension filters | `QueryFilter('EXT=<ext>')`, OR-ed as `SetOrFilter` |
| SQL seam | `lib/features/collection_paging/query/collection_filter_sql.dart` |
| Rule check | `scripts/check-search-filters-rules.ps1` |

## Reading order

1. `spec.md` — what each condition means and how it composes.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the value, the SQL fragments and the two windows.
4. `decisions/` — why the span is persisted, why one range type, why a missing
   value never matches.
5. `testing.md` — the SQL-parity fixture and the sheet checks.

## Code map

| Layer | Path |
| --- | --- |
| Assist value | `lib/features/search_filters/model/search_assist.dart` |
| Relative window | `lib/features/search_filters/model/relative_time_filter.dart` |
| Numeric range | `lib/features/search_filters/model/range_assist_filter.dart` |
| Token | `lib/features/search_filters/model/time_to_now.dart` |
| Size units | `lib/features/search_filters/model/size_assist_unit.dart` |
| Count | `lib/features/search_filters/services/assist_counter.dart` |
| Sheets and section | `lib/features/search_filters/view/` |
| SQL | `lib/features/collection_paging/query/collection_filter_sql.dart` |
| Search page wiring | `lib/widgets/search/collection_search_delegate.dart` |
| Tests | `test/features/search_filters/` |

## Privacy note

Fixtures use stand-in folders and numbered entries. See `docs/README.md`.
