# Session restore — testing

## Host coverage

Three files, all against fakes and injected preferences:

- `session_restore_store_test.dart` — snapshot decoding (round-trip, unknown
  route, malformed JSON, an unreadable filter, base validation, the older
  route-only record) and the store (save/load/clear, invalid writes, and the
  three failure paths).
- `session_restore_route_observer_test.dart` — the tracked stack: push, pop,
  remove, replace, the nearest restorable base, transient pages above and below,
  and the wallpaper page over the range page.
- `session_restore_plan_test.dart` — the pure plan: filters only for the
  collection, empty set versus `null`, base filters only for a collection base,
  the stand-in home page and its self-page fallback, and the sub-page flag.

The store tests use `SharedPreferences.setMockInitialValues`; the failure tests
inject a provider that throws, which is why `SessionRestoreStore` takes a
`prefsProvider`.

## Device steps

These cover the lifecycle rows, which live in the app widget:

| Row | Step |
| --- | --- |
| SRS-1, SRS-8 | Open the collection with a filter, background the app, swipe it from recents or kill it, relaunch: the same page and filters come back |
| SRS-9 | Open a picker from another app's share sheet, background and relaunch plainly: the previous main page comes back, not the picker |
| SRS-11 | Press back out of the main page, relaunch: the configured home page opens |
| SRS-12 | Swipe the task from recents, relaunch: the configured home page opens |
| SRS-15 | Share a photo into the app, then relaunch plainly: the main page opens, not the share target |
| SRS-18 | Open the grouped wallpaper page from the collection, kill the app, relaunch: the collection is under it, and back returns there |

## Not host-testable

- The lifecycle save/clear and the plain-launch detection read
  `AppLifecycleState`, the app-mode notifier and the launch intent inside
  `AvesApp`/`HomePage`; a widget test would need the whole app environment.
- The base-then-top push order needs a live `Navigator` and the redirect route
  resolver.
- The viewer, explorer and picker limits follow from the route allow-list: the
  observer and plan tests already pin which names are restorable.

## Discipline

- A new top-level page is either added to `restorableSessionRoutes` with a
  decision, or explicitly left out; the allow-list is the review surface.
- A snapshot field is added, never renamed: the record has no schema version.
- A change to the base rules updates both the reader test and the plan test; they
  are the two halves of one predicate.
