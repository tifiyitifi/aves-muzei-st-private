# Session restore — design

## The snapshot

```text
route        the top restorable page
filters      the collection filters, only for the collection
baseRoute    the page below a pushed page, only for a pushed page
baseFilters  the base collection's filters, only when the base is the collection
rangeWallpaper  the shared visible-range entry's wallpaper sub-page
```

It is one JSON string under one `SharedPreferences` key
(`session_restore.snapshot`). The store deliberately does not go through
`SettingsStore`, the settings-engine router or the database: a snapshot is a
session artifact, not a setting, so the `settings_engine` gate has no say in it
and clearing is one `remove`.

`SessionRestoreSnapshot.tryFromJsonString` ignores unknown keys and validates the
known ones. Filters decode through `CollectionFilter.fromJson`, so one unreadable
entry is dropped while the rest survive. A stored base survives only when the
top page is a pushed page, the base is restorable and the base differs from the
page; otherwise both the base and its filters are dropped and the page is kept.
`rangeWallpaper` survives only on the visible-range route. The same predicate
(`isValid`) guards `save`, so the writer cannot persist a record the reader would
reject.

## The observer

`SessionRestoreRouteObserver` keeps the root navigator's `Route` list and answers
two questions:

- `currentRestorableRoute` — the topmost route whose name is in the allow-list,
  so a transient sub-page (wallpaper sources, gestures, history) neither becomes
  the destination nor hides the page below it;
- `currentRestorableBaseRoute` — only for a pushed page, the nearest restorable
  route below it.

`didReplace` puts the new route in the old one's slot; an unknown old route is
appended. Because the observer is registered on the root `MaterialApp` only, the
wallpaper picker's nested navigator is invisible to it.

## The plan

`planSessionRestore` is pure: snapshot + configured home route in, a plan record
out.

```text
filters      = snapshot.filters   when the page is the collection, else null
baseRouteName = savedBase ?? standInBase   for a pushed page, else null
baseFilters  = snapshot.baseFilters   only when the base is the collection
rangeWallpaper = snapshot.rangeWallpaper && page is the visible-range route
standInBase  = homeRouteName == page ? collection : homeRouteName
```

`null` and `{}` are different states: `null` means "use the configured default"
(the home collection, or the page's own settings), `{}` means "all media".
`home_page.dart` resolves `overrideFilters ?? initialFilters ?? homeCustomCollection`,
so an empty saved set restores all media rather than the home collection.

## Integration seams

| Seam | File | Contract |
| --- | --- | --- |
| Lifecycle | `lib/widgets/aves_app.dart` | save on `inactive`/`paused` only in main mode with an initialized `Settings` and a restorable route; clear on back-out and `detached` |
| Restore | `lib/widgets/home/home_page.dart` | a launch without intent data loads the snapshot, plans it, sets the initial route/filters and, for a pushed page, pushes the base then the top |
| Collection filters | `lib/widgets/collection/collection_page.dart` and `session_restore_collection_state.dart` | the mounted collection is the only writer; live query filters and picker collections are excluded; a process-wide holder survives a page rebuild before the pause |

The snapshot is not cleared after a restore: a second plain launch reopens the
same page until the next main-mode pause overwrites it or the app is backed out
of or detached.

## Anti-patterns

- Serializing the navigator stack: most pages need constructor arguments that
  cannot be rebuilt from a name.
- Restoring scroll, camera, selection or search: those live in widgets that no
  longer exist.
- Writing a snapshot outside main mode: a picker would overwrite the user's page.
- Treating a snapshot as a setting: it would inherit the settings engine's
  migration, seeding and gate for no benefit.
