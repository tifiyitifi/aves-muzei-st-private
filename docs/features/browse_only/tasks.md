# Browse only — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| Host test for `BrowsePrefs` | defaults, the read fallback, the no-op guard and the four keys are all fake-`SharedPreferences` testable; today the preference rows are unfalsified | `PRF-1`, `PRF-2` |
| Extract and test the viewer window bounds | `openBrowseOnlyViewer` clamps the position and slices ±250 neighbours; a pure helper would be host-testable | `UI-2` |
| Widget test for the page chrome | title derivation from the user's navigation, the spinner, the first-page error bar and the preview strip's two actions | `UI-3`, `UI-4` |
| Test the handoff clear | `CollectionPage` clears both singletons when the phase reaches ready; the windows' own `clear` is tested, the wiring is not | `NAV-3` |
| Give the slice its own log channel | all three services log on `log.collection_paging`; `AGENTS.md` asks a slice to declare its own key | — |
| Decide whether the preview strip should count hidden rows | `atLimit` uses the raw row count, so the strip can claim more rows than the grid shows | `WIN-10` (design) |
| Fix the stale sort-preference load | `browsePrefs.init()` runs only from the timeline, so opening Albums first shows defaults while its sort picker writes the same keys | `PRF-1` |
| Remove the unused `months`/`videoIndexes` API | no production caller; only `browse_library_test` keeps them alive | `ORD-3`, `ORD-4` |

Not planned: restoring selection or editing in the browser. It is a viewing
surface by design (`0001`).
