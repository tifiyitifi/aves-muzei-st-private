# Session restore — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-session-restore-rules.ps1` resolves every `F:`
token.

## Snapshot content

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SRS-1 | Top page | WHEN a restorable page is on top in main mode, THE SYSTEM SHALL record its route name | without a route there is nothing to reopen | `M` |
| SRS-2 | Collection filters | WHEN the recorded page is the collection, THE SYSTEM SHALL record the filters on screen | "the collection" means the media set the user had, not every entry | `F:session_restore_store_test#round-trips the route and its filters` |
| SRS-3 | No filters elsewhere | WHEN the recorded page is not the collection, THE SYSTEM SHALL carry no filter set | a filter set on a map or album page would reopen the wrong media | `F:session_restore_store_test#accepts a page without filters`; `F:session_restore_plan_test#restores an ordinary page alone, with filters only for the collection` |
| SRS-4 | Base page | WHEN the top page is a pushed wallpaper page, THE SYSTEM SHALL record the nearest restorable page below it | the back target is part of where the user was | `F:session_restore_store_test#round-trips the page a pushed page was opened from`; `F:session_restore_route_observer_test#a pushed page reports the page it was opened from` |
| SRS-5 | Base filters | WHEN the base is the collection, THE SYSTEM SHALL record the base collection's filters | the base must reopen the set the user was browsing | `F:session_restore_plan_test#restores a pushed page over the page it was opened from` |
| SRS-6 | Shared entry | WHEN the visible-range route showed its wallpaper sub-page, THE SYSTEM SHALL record that sub-page | one route hosts two pages; the route name alone restores the wrong one | `F:session_restore_store_test#round-trips the shared entry sub-page` |
| SRS-7 | Flag normalisation | WHEN the top page is not the visible-range route, THE SYSTEM SHALL read the sub-page flag as off | a hand-edited or stale flag must not turn a page into the wallpaper one | `F:session_restore_store_test#keeps the sub-page flag off every other route`; `F:session_restore_plan_test#carries the shared entry sub-page for the range route only` |

## Writing and clearing

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SRS-8 | Lifecycle write | WHEN the app enters `inactive` or `paused` in main mode, THE SYSTEM SHALL persist the snapshot | a paused app may be killed without another callback | `M` |
| SRS-9 | Main surface only | WHEN the app is not on its main surface, THE SYSTEM SHALL write no snapshot | a picker or an external view would overwrite the user's page | `M` |
| SRS-10 | Invalid write | WHEN the snapshot is invalid, THE SYSTEM SHALL not persist it | the writer must not create a record the reader rejects | `F:session_restore_store_test#does not persist an invalid route`; `F:session_restore_store_test#does not persist a base saved under a page that is not pushed` |
| SRS-11 | Back-out clears | WHEN the user backs out of the main page, THE SYSTEM SHALL clear the snapshot | leaving the app means "next launch starts fresh" | `M` |
| SRS-12 | Task swipe clears | WHEN the lifecycle reaches `detached`, THE SYSTEM SHALL clear the snapshot | the task is gone, so the page must not come back | `M` |
| SRS-13 | Store failure | WHEN the store fails to read, THE SYSTEM SHALL report no snapshot instead of failing | a missing convenience must not block the app start | `F:session_restore_store_test#a store that cannot read reports no snapshot` |
| SRS-14 | Failed write or clear | WHEN the store fails to write or clear, THE SYSTEM SHALL log the failure and continue | the snapshot is not load-bearing for the current session | `F:session_restore_store_test#a store that cannot write still completes`; `F:session_restore_store_test#a store that cannot clear still completes` |

## Restoring

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SRS-15 | Plain launch only | WHEN a launch carries no intent data, THE SYSTEM SHALL reopen the recorded page | an intent names its own destination, which wins | `M` |
| SRS-16 | Collection restore | WHEN the recorded page is the collection, THE SYSTEM SHALL reopen it with the recorded filters | the filters are the page | `F:session_restore_plan_test#restores an ordinary page alone, with filters only for the collection` |
| SRS-17 | Empty set is not "unset" | WHEN the collection was saved with an empty filter set, THE SYSTEM SHALL restore "all media", not the configured home collection | an empty set is a real state; only `null` means "use the default" | `F:session_restore_plan_test#keeps an empty collection set distinct from the home collection` |
| SRS-18 | Base first | WHEN the top page is pushed with a base, THE SYSTEM SHALL rebuild the base and then push the top page | pushing first would leave nothing under the back gesture | `M` |
| SRS-19 | Base collection filters | WHEN the base is the collection, THE SYSTEM SHALL reopen it with the recorded base filters | a different set would make the base a different page | `F:session_restore_plan_test#restores a pushed page over the page it was opened from` |
| SRS-20 | No invented filters | WHEN the base is not the collection, THE SYSTEM SHALL let it rebuild from its own settings | a filter set belongs to the collection only | `F:session_restore_plan_test#does not invent filters for a base that is not the collection` |
| SRS-21 | Stand-in base | WHEN a pushed page was saved without a base, THE SYSTEM SHALL use the configured home page | the user's home is the honest page under it | `F:session_restore_plan_test#stands the configured home page in for a snapshot saved without a base` |
| SRS-22 | Self base | WHEN the configured home page is the pushed page itself, THE SYSTEM SHALL use the collection as the base | the same page twice is not a stack | `F:session_restore_plan_test#stands a collection in when the home page is the pushed page itself` |
| SRS-23 | Pushed-page rule | WHEN a base was saved under a page that is not pushed, THE SYSTEM SHALL ignore the base | only a pushed page has a back target worth restoring | `F:session_restore_plan_test#ignores a base saved under a page that is not pushed` |
| SRS-24 | Wallpaper over anything | WHEN the grouped wallpaper page was over the range page, THE SYSTEM SHALL restore that pair | the wallpaper page is pushed over whatever opened it | `F:session_restore_route_observer_test#the wallpaper page is restored over the page it was opened from`; `F:session_restore_plan_test#restores the wallpaper page over the page it was opened from` |

## Reading a stored snapshot

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SRS-25 | Unknown route | WHEN the stored route is missing, not a string, or not restorable, THE SYSTEM SHALL treat the snapshot as absent | a route the build cannot open must not crash the launch | `F:session_restore_store_test#rejects a route the app cannot reopen`; `F:session_restore_store_test#tolerates malformed or empty input` |
| SRS-26 | Unusable base | WHEN the stored base is not restorable, THE SYSTEM SHALL drop the base and keep the page | losing the back target beats losing the page | `F:session_restore_store_test#drops an unusable base but keeps the page` |
| SRS-27 | Self base | WHEN the stored base equals the page, THE SYSTEM SHALL drop the base and keep the page | a page cannot sit over itself | `F:session_restore_store_test#drops a base pointing at the page itself` |
| SRS-28 | Unpushed base | WHEN the stored base sits under a page that is not pushed, THE SYSTEM SHALL drop the base and keep the page | the pair is not rebuildable | `F:session_restore_store_test#drops a base saved under a page that is not pushed` |
| SRS-29 | Reader/writer split | WHEN a base is constructed under a page that is not pushed, THE SYSTEM SHALL call the snapshot invalid | the writer must reject what the reader would silently drop | `F:session_restore_store_test#considers a base saved under a page that is not pushed invalid` |
| SRS-30 | Older snapshot | WHEN a stored snapshot carries only a route, THE SYSTEM SHALL still accept it | a snapshot written before the base field must survive an upgrade | `F:session_restore_store_test#reads a snapshot saved before the base page existed` |
| SRS-31 | Bad filter | WHEN a stored filter cannot be parsed, THE SYSTEM SHALL skip that filter and keep the rest | one unreadable filter must not cost the page | `F:session_restore_store_test#skips a stored filter it cannot parse` |

## Navigation tracking

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SRS-32 | Nearest restorable base | WHEN the page under a pushed page is not restorable, THE SYSTEM SHALL report the nearest restorable one below it | transient sub-pages must not become the back target | `F:session_restore_route_observer_test#the base is the nearest restorable page below`; `F:session_restore_route_observer_test#a non-restorable page below leaves no base` |
| SRS-33 | Transient page on top | WHEN a non-restorable page is pushed over a pushed page, THE SYSTEM SHALL keep the pushed page as the top | a sources or gestures page is not a destination | `F:session_restore_route_observer_test#a non-restorable page above the pushed page does not move the base`; `F:session_restore_route_observer_test#a page above the wallpaper page does not move the base` |
| SRS-34 | Pop | WHEN the pushed page is popped, THE SYSTEM SHALL report the page below it | the stack, not a counter, decides | `F:session_restore_route_observer_test#popping the pushed page restores the ordinary behavior` |
| SRS-35 | Remove | WHEN a page is removed from the stack, THE SYSTEM SHALL stop reporting it | a swallowed page cannot be reopened | `F:session_restore_route_observer_test#a page removed from the stack can no longer be restored` |
| SRS-36 | Replace | WHEN a page is replaced, THE SYSTEM SHALL put the new page in the old one's slot | a replace must not grow the stack | `F:session_restore_route_observer_test#a replaced page takes the old page slot`; `F:session_restore_route_observer_test#replacing an unknown page appends the new one` |
| SRS-37 | Root navigator only | WHEN a nested navigator pushes pages, THE SYSTEM SHALL not treat them as the app's page | the wallpaper picker must not become the restored destination | `-:only the root navigator is observed (aves_app.dart); a nested one is outside the observer` |

## Limits

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SRS-38 | Viewer set, not photo | WHEN the user was in the viewer, THE SYSTEM SHALL restore the media set under it | a viewer entry is not restorable, but its collection is | `-:the viewer route is outside the allow-list; the restore seam needs the app widget` |
| SRS-39 | Explorer | WHEN the user was in the explorer, THE SYSTEM SHALL reopen the configured home page | a browsed path is not part of the snapshot | `-:the explorer route is outside the allow-list` |
| SRS-40 | Picker or external view | WHEN a picker or an external view had the foreground, THE SYSTEM SHALL not restore it | the app was opened for one task | `-:the app-mode gate lives in the app widget (see testing.md)` |
| SRS-41 | No transient state | WHEN a snapshot is restored, THE SYSTEM SHALL not restore a scroll position, a camera, a selection or a search | those live in widgets that no longer exist | `-:the snapshot has no field for them; a test would assert the absence of a field, not a behaviour` |
