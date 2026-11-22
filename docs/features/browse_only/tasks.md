# Browse only — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| Test the handoff clear | `CollectionPage` clears both singletons when the phase reaches ready; the windows' own `clear` is tested, the wiring is not. Deferred: a real test needs a `CollectionPage` fixture (providers, source, lens) | `NAV-3` |
| Cover the viewer's detached lens | `openBrowseOnlyViewer` builds a `CollectionLens(listenToSource: false)`; the window arithmetic is covered, the lens choice needs the viewer route and a collection source | — |

Not planned: restoring selection or editing in the browser. It is a viewing
surface by design (`0001`).
