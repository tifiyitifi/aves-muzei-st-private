# Browse only — open work

No open correctness work. The item below is a follow-up found while writing the
register.

| Item | Why | Rule |
| --- | --- | --- |
| Test the handoff clear | `CollectionPage` clears both singletons when the phase reaches ready; the windows' own `clear` is tested, the wiring is not. Deferred: a real test needs a `CollectionPage` fixture (providers, source, lens) | `NAV-3` |

Not planned: restoring selection or editing in the browser. It is a viewing
surface by design (`0001`).
