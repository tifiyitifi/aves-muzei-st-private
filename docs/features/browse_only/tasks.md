# Browse only — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| Widget test for the page chrome | title derivation from the user's navigation, the spinner, the first-page error bar and the preview strip's two actions | `UI-3`, `UI-4` |
| Test the handoff clear | `CollectionPage` clears both singletons when the phase reaches ready; the windows' own `clear` is tested, the wiring is not. Deferred: a real test needs a `CollectionPage` fixture (providers, source, lens) | `NAV-3` |
| Decide whether the preview strip should count hidden rows | `atLimit` uses the raw row count, so the strip can claim more rows than the grid shows | `WIN-10` (design) |

Not planned: restoring selection or editing in the browser. It is a viewing
surface by design (`0001`).
