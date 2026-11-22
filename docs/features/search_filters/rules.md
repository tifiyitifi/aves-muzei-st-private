# Search filters (assist) — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-search-filters-rules.ps1` resolves every `F:`
token.

## The token

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| T2N-1 | Parse | WHEN a token is an amount followed by `h` or `d`, THE SYSTEM SHALL parse it, ignoring case and spaces | the token is hand-editable in presets | `F:time_to_now_test#parses hour and day tokens` |
| T2N-2 | Reject | WHEN a token is malformed, zero or negative, THE SYSTEM SHALL reject it | a `0d` window would look like an empty library | `F:time_to_now_test#rejects malformed and zero-width tokens` |
| T2N-3 | Serialize | WHEN a span is serialized, THE SYSTEM SHALL emit a token that parses back to the same value | the preset document stores the token | `F:time_to_now_test#round-trips through its token` |
| T2N-4 | Window length | WHEN a span's length is read, THE SYSTEM SHALL resolve hours and days to milliseconds | the cutoff and the SQL fragment share it | `F:time_to_now_test#resolves its window in milliseconds` |

## The relative window

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| RTF-1 | Anchor once | WHEN a relative filter is constructed, THE SYSTEM SHALL anchor its cutoff once | a long browse must not move the window under the user | `F:relative_time_filter_test#the window is anchored at construction` |
| RTF-2 | Window test | WHEN a relative filter tests an entry, THE SYSTEM SHALL accept it from the cutoff on, and reject an undated entry | "last 7 days" means a date, not every unknown date | `F:relative_time_filter_test#matches only entries inside the window` |
| RTF-3 | Reversed window | WHEN a relative filter is reversed, THE SYSTEM SHALL keep the undated entries | the complement of "has a recent date" includes "no date" | `F:relative_time_filter_test#a reversed window keeps the undated entries` |
| RTF-4 | Equality | WHEN two relative filters are compared, THE SYSTEM SHALL ignore the anchor | a restored filter must dedupe with the one it came from | `F:relative_time_filter_test#round-trips through JSON and re-anchors on restore` |
| RTF-5 | JSON | WHEN a relative filter round-trips, THE SYSTEM SHALL persist span and reversal and re-anchor | persisting the instant would freeze the window | `F:relative_time_filter_test#round-trips through JSON and re-anchors on restore` |
| RTF-6 | Corrupt span | WHEN a stored span is corrupt, THE SYSTEM SHALL drop the filter instead of raising | one bad preset must not break the filter list | `F:relative_time_filter_test#a corrupt span is dropped instead of crashing` |
| RTF-7 | Assist parity | WHEN the assist holds a recent window, THE SYSTEM SHALL build the same relative filter | two constructors would drift | `F:relative_time_filter_test#the assist builds the same condition` |
| RTF-8 | Reversal keeps the anchor | WHEN a relative filter is reversed, THE SYSTEM SHALL keep the window's cutoff and only flip the condition | a visible range uses the positive filter for browsing and its reversal for the summary exclusion; two anchors would stop the sides partitioning the library | `F:relative_time_filter_test#reversing keeps the window anchor` |

## The numeric range

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| RNG-1 | Inclusive bounds | WHEN a range is tested, THE SYSTEM SHALL include both bounds | "1 to 5 MB" includes 1 and 5 | `F:range_assist_filter_test#a date range is inclusive` |
| RNG-2 | Missing value | WHEN the entry has no value for the field, THE SYSTEM SHALL not match it, while its reversed form SHALL | "no date" is not "before 2020" | `F:range_assist_filter_test#a missing date never matches, even a max-only range` |
| RNG-3 | Size | WHEN the field is the size, THE SYSTEM SHALL read the file size | the sheet's presets are byte bounds | `F:range_assist_filter_test#a size range reads the file size` |
| RNG-4 | Dimensions | WHEN the field is the width or height, THE SYSTEM SHALL read the displayed size | the user reasons about the picture as shown | `F:range_assist_filter_test#width and height read the displayed size` |
| RNG-5 | Rotation | WHEN the entry is rotated a quarter turn, THE SYSTEM SHALL swap the displayed width and height | a portrait photo is tall on screen | `F:range_assist_filter_test#the displayed size swaps for a rotated entry` |
| RNG-6 | Content id | WHEN the field is a content id, THE SYSTEM SHALL match only entries that carry one | a missing id is not a small id | `F:range_assist_filter_test#a content id range ignores entries without one` |
| RNG-7 | JSON | WHEN a range round-trips, THE SYSTEM SHALL preserve field, bounds and reversal | a saved filter must reopen as itself | `F:range_assist_filter_test#round-trips through JSON` |
| RNG-8 | Unknown field | WHEN the stored field is unknown, THE SYSTEM SHALL drop the filter | an unknown field has no predicate | `F:range_assist_filter_test#an unknown field is dropped instead of crashing` |

## Composition

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| AST-1 | Empty | WHEN the assist is empty, THE SYSTEM SHALL build nothing and report itself empty | an empty sheet must not filter the library | `F:search_assist_test#an empty assist builds nothing` |
| AST-2 | Path | WHEN a path condition is set, THE SYSTEM SHALL build one directory filter, reversed when excluded | the path is one condition, not a query | `F:search_assist_test#a path condition is the single directory filter` |
| AST-3 | Path is not "other" | WHEN only a path is set, THE SYSTEM SHALL not report "other" conditions | the two chips light independently | `F:search_assist_test#a path alone is not an "other" condition` |
| AST-4 | Ranges | WHEN date, size and content-id ranges are set, THE SYSTEM SHALL build one filter each | one type, one filter per field | `F:search_assist_test#date, size and id become one ranged filter each` |
| AST-5 | Dimensions | WHEN a dimension range is set, THE SYSTEM SHALL build separate width and height filters | the two fields have separate bounds | `F:search_assist_test#a dimension range expands to width and height` |
| AST-6 | Empty dimension | WHEN the dimension range is empty, THE SYSTEM SHALL add nothing | an empty range is not "match all" | `F:search_assist_test#an empty dimension adds nothing` |
| AST-7 | Recent | WHEN a recent window is set, THE SYSTEM SHALL build a relative filter with that span | the window is the same condition as a preset | `F:search_assist_test#a recent window becomes a relative filter` |
| AST-8 | Extensions | WHEN one extension is set, THE SYSTEM SHALL build the single `EXT=` query; WHEN several, THE SYSTEM SHALL OR them | the query compiler owns extension matching | `F:search_assist_test#one extension is a query, several are OR-ed` |
| AST-9 | Normalisation | WHEN extensions are stored, THE SYSTEM SHALL lowercase them and strip the dot | `JPG`, `.jpg` and `jpg` are one format | `F:search_assist_test#extensions are stored without a dot and lowercased` |
| AST-10 | Remove one | WHEN one condition is removed, THE SYSTEM SHALL keep the others | a chip drops its own field only | `F:search_assist_test#removing one condition keeps the others` |
| AST-11 | Clear others | WHEN the "other" conditions are cleared, THE SYSTEM SHALL keep the path | the path chip has its own sheet | `F:search_assist_test#clearing the other conditions keeps the path` |
| AST-12 | Conjunction | WHEN every field is set, THE SYSTEM SHALL build one filter per condition | the conditions AND | `F:search_assist_test#every condition together is a conjunction of filters` |

## SQL parity

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SQL-1 | Taken date | WHEN a taken-date range compiles, THE SYSTEM SHALL read the same best-date expression as the in-memory test | a paged browse and a legacy browse must agree | `F:assist_sql_test#a taken date range` |
| SQL-2 | Size | WHEN a size range compiles, THE SYSTEM SHALL read `COALESCE(size, 0)` | a null size is zero bytes on both sides | `F:assist_sql_test#a size range` |
| SQL-3 | Width | WHEN a width range compiles, THE SYSTEM SHALL swap sides for a quarter-turn rotation | the displayed size is what the user picked | `F:assist_sql_test#a width range` |
| SQL-4 | Height | WHEN a height range compiles, THE SYSTEM SHALL swap sides for a quarter-turn rotation | same | `F:assist_sql_test#a height range` |
| SQL-5 | Content id | WHEN a content-id range compiles, THE SYSTEM SHALL exclude rows without an id | the Dart test does | `F:assist_sql_test#a content id range` |
| SQL-6 | Reversed | WHEN a filter is reversed, THE SYSTEM SHALL keep the rows the positive test rejects, NULL included | a NULL-unsafe negation loses the undated row | `F:assist_sql_test#a reversed range keeps the entries the positive test rejects` |
| SQL-7 | Window anchor | WHEN a relative window compiles, THE SYSTEM SHALL compare against the filter's own cutoff | SQL must not read the clock | `F:assist_sql_test#a relative window uses the filter anchor` |
| SQL-8 | Whole set | WHEN an assist set compiles, THE SYSTEM SHALL AND the fragments and join only what each field needs | one query per assist | `F:assist_sql_test#the whole assist set compiles and matches` |

## Counting

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CNT-1 | Empty set | WHEN the condition set is empty, THE SYSTEM SHALL report no count | an empty sheet must not claim the whole library | `F:assist_counter_test#an empty condition reports no count` |
| CNT-2 | Inexpressible condition | WHEN a condition has no SQL translation, THE SYSTEM SHALL report no count | an in-memory scan would block the sheet | `F:assist_counter_test#a condition with no SQL translation reports no count` |
| CNT-3 | Unready store | WHEN the store cannot answer, THE SYSTEM SHALL report no count instead of failing | the number is advisory | `F:assist_counter_test#a database that cannot open reports no count` |
| CNT-4 | Hidden albums | WHEN hidden albums are configured, THE SYSTEM SHALL leave them out | the count must match the grid | `F:assist_counter_test#a hidden album is not counted` |
| CNT-5 | Locked vaults | WHEN a vault is locked, THE SYSTEM SHALL leave its rows out | a locked vault stays in the database but not in browsing | `F:assist_counter_test#a locked vault is not counted` |
| CNT-6 | Stacks | WHEN a stack hides its members, THE SYSTEM SHALL count the tile once | the grid shows one tile | `F:assist_counter_test#a stack member does not count twice` |
| CNT-7 | Visible range | WHEN a range is active, THE SYSTEM SHALL count inside it | the sheet describes what the user can browse | `-:the gate itself is covered by visible_range; the counter composes it as-is` |

## Sheets and section

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| ASI-1 | Advisory count | WHEN the sheet shows a match count, THE SYSTEM SHALL omit it rather than block | the count is a hint, not the view's total | `F:assist_counter_test#a condition with no SQL translation reports no count`; `F:assist_counter_test#a database that cannot open reports no count` |
| ASI-2 | Path sheet | WHEN the path sheet opens, THE SYSTEM SHALL browse storage volumes and directories | the folder picker is the platform's | `-:needs Android storage volumes and dart:io listings; device-level` |
| ASI-3 | Date presets | WHEN a date preset is chosen, THE SYSTEM SHALL compute a local-day window | a preset is two bounds, not a new filter type | `-:layout and a date picker; device-level` |
| ASI-4 | Size unit | WHEN the size unit changes, THE SYSTEM SHALL keep the byte value | a unit change must not change the filter | `F:size_assist_unit_test#converting a unit keeps the byte value`; `F:size_assist_unit_test#a round trip through two units returns to the same bound` |
| ASI-8 | Reopened bound | WHEN a stored bound is reloaded, THE SYSTEM SHALL pick the largest exact unit and show the same byte value | rounding on reopen would silently move a size the user set | `F:size_assist_unit_test#the largest exact unit is chosen for a stored bound`; `F:size_assist_unit_test#a tiny non-zero bound does not become no bound` |
| ASI-9 | Empty size field | WHEN a size field is blank or not positive, THE SYSTEM SHALL treat it as no bound | `0` is not a size | `F:size_assist_unit_test#an empty or negative field is no bound` |
| ASI-10 | Counting while typing | WHEN the draft changes repeatedly, THE SYSTEM SHALL count once after the edits settle | counting each keystroke would queue SQL the user never waits for | `F:count_debouncer_test#rapid edits run one count after the delay` |
| ASI-11 | Stale count | WHEN a count answers after a newer edit, THE SYSTEM SHALL discard it | a slow reply must not overwrite the number of the current draft | `F:count_debouncer_test#a late answer does not overwrite a newer one`; `F:count_debouncer_test#an answer for a closed sheet is dropped` |
| ASI-5 | Inverted bounds | WHEN the lower bound exceeds the upper, THE SYSTEM SHALL refuse to apply | a silent swap would change the meaning | `-:layout; Done is disabled, asserted by no host test` |
| ASI-6 | Apply is additive | WHEN the user applies, THE SYSTEM SHALL add the built filters to the typed query | "apply conditions" means add, not replace | `-:the delegate owns the apply path; no host test (see tasks.md)` |
| ASI-7 | Unit labels | WHEN the unit menu renders, THE SYSTEM SHALL label each unit from the localization | a hardcoded symbol never follows the app language | `-:the labels come from ARB keys, so a missing one is a compile error; the menu is layout` |
