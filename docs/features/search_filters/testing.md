# Search filters (assist) — testing

## Host coverage

- `time_to_now_test.dart` — token parsing, rejection, round-trip, window length.
- `relative_time_filter_test.dart` — the window at construction and on test, the
  reversed window with undated entries, equality ignoring the anchor, JSON, a
  corrupt span, and the assist parity.
- `range_assist_filter_test.dart` — inclusive bounds, missing values, each field's
  value (best date, size, displayed size including rotation, content id), JSON and
  an unknown field.
- `search_assist_test.dart` — every composition rule: path, ranges, dimensions,
  recent, extensions, removal, clearing, and the full conjunction.
- `assist_sql_test.dart` — the parity fixture: an in-memory Drift database with
  four rows (day 0, day 1 with a size and a width, day 3 with another, one undated
  row), where each test asserts that the SQL ids equal the in-memory predicate's
  ids, both positive and reversed.

The parity fixture is the important one: a mismatch between the two engines is a
library that changes shape when the paged engine kicks in.

## Sheet checks

The two sheets are layout; verify on a device:

| Check | Steps |
| --- | --- |
| Path include/exclude | Pick a folder with include, apply, then repeat with exclude; both chips show the folder |
| Date presets | Choose "last 7 days"; the count drops and the chip reads the same preset |
| Custom range | Pick a start/end day; the window covers the whole first and last day |
| Size units | Enter 1 GB, switch to MB and back; the byte-bound is unchanged |
| Inverted bounds | Set a minimum above the maximum; Done is disabled |
| Extensions | Pick two formats; the chip count is one and the result is their union |
| Apply is additive | Type a query, then apply an assist; the result honours both |

## Debt

These are testable on the host but have no test yet; they are listed here rather
than claimed by a rule:

- `AssistCounter.count` — the null guards (empty, unexpressible, unready, error),
  the visible-range augmentation and the hidden filters.
- The 300 ms debounce and the stale-result token in the "more filters" sheet.
- The size-unit conversion and the "largest exact unit" choice.
- Inverted-bound gating in the sheet.

The visible-range presets reuse `RelativeTimeFilter`; their own register covers
the shipped bundle.

## Discipline

- A new field starts with its in-memory test, its SQL parity test and a
  `RangeAssistFilter` case, in that order.
- A change to the relative window updates the SQL fragment and the parity test
  together: the two engines must never disagree.
- A new preset is data in `assets/visible_range_presets.json`, not a new filter
  type.
