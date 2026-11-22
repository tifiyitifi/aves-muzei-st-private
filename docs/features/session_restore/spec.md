# Session restore — requirements

## What is remembered

- WHEN the app is in main mode and a restorable page is on top, THE SYSTEM SHALL
  record that page's route name.
- WHEN the recorded page is the collection, THE SYSTEM SHALL record the filters
  of the collection on screen.
- WHEN the recorded page is not the collection, THE SYSTEM SHALL record no filter
  set for it.
- WHEN the recorded page is a pushed wallpaper page, THE SYSTEM SHALL record the
  nearest restorable page below it as the base.
- WHEN the recorded base is the collection, THE SYSTEM SHALL record the base
  collection's filters.
- WHEN the top page is the visible-range route and the shared entry was showing
  the wallpaper page, THE SYSTEM SHALL record that sub-page.
- WHEN the top page is any other route, THE SYSTEM SHALL record the shared-entry
  flag as off.

## When it is written and cleared

- WHEN the app lifecycle enters `inactive` in main mode, THE SYSTEM SHALL persist
  the snapshot.
- WHEN the app lifecycle enters `paused` in main mode, THE SYSTEM SHALL persist
  the snapshot.
- WHEN the app is not on its main surface (a picker, an external view, a screen
  saver), THE SYSTEM SHALL write no snapshot.
- WHEN settings have not finished initializing, THE SYSTEM SHALL write no
  snapshot.
- WHEN no restorable page is on the stack, THE SYSTEM SHALL write no snapshot.
- WHEN the snapshot is invalid, THE SYSTEM SHALL not persist it.
- WHEN the user backs out of the main page, THE SYSTEM SHALL clear the snapshot.
- WHEN the app lifecycle reaches `detached`, THE SYSTEM SHALL clear the snapshot.

## When it is restored

- WHEN a launch carries no intent data, THE SYSTEM SHALL reopen the recorded
  page.
- WHEN a launch carries intent data, THE SYSTEM SHALL ignore the snapshot.
- WHEN the recorded top page is the collection, THE SYSTEM SHALL reopen it with
  the recorded filters.
- WHEN the recorded top page is a pushed page with a recorded base, THE SYSTEM
  SHALL rebuild the base first and push the top page over it.
- WHEN the recorded base is the collection, THE SYSTEM SHALL reopen it with the
  recorded base filters.
- WHEN a pushed page was saved without a base, THE SYSTEM SHALL use the
  configured home page as the base.
- WHEN the configured home page is the pushed page itself, THE SYSTEM SHALL use
  the collection as the base.
- WHEN the stand-in base is not the collection, THE SYSTEM SHALL let it rebuild
  from its own settings.
- WHEN the restored route is the visible-range route and the snapshot carries the
  wallpaper sub-page, THE SYSTEM SHALL open that sub-page.
- WHEN a snapshot carries the sub-page flag for another route, THE SYSTEM SHALL
  ignore it.

## Refusals and staleness

- WHEN the stored route is missing, not a string, or not restorable, THE SYSTEM
  SHALL treat the snapshot as absent.
- WHEN the stored JSON is empty or malformed, THE SYSTEM SHALL treat the snapshot
  as absent and log a warning.
- WHEN the stored base is not restorable, THE SYSTEM SHALL drop the base and keep
  the page.
- WHEN the stored base is the page itself, THE SYSTEM SHALL drop the base and
  keep the page.
- WHEN the stored base sits under a page that is not a pushed page, THE SYSTEM
  SHALL drop the base and keep the page.
- WHEN the base is dropped, THE SYSTEM SHALL drop its filters too.
- WHEN a stored filter cannot be parsed, THE SYSTEM SHALL skip that filter and
  keep the rest.
- WHEN a stored snapshot predates the base field, THE SYSTEM SHALL still accept
  it.
- WHEN the store fails to read, write or remove, THE SYSTEM SHALL log the failure
  and leave the previous state.

## Navigation tracking

- WHEN a route is pushed on the observed navigator, THE SYSTEM SHALL track it.
- WHEN a route is popped or removed, THE SYSTEM SHALL stop tracking it.
- WHEN a route is replaced, THE SYSTEM SHALL put the new route in the old one's
  place.
- WHEN the top of the stack is not restorable, THE SYSTEM SHALL report the
  topmost restorable page below it.
- WHEN the reported page is pushed, THE SYSTEM SHALL report the nearest
  restorable page below it as the base.
- WHEN there is no restorable page below a pushed one, THE SYSTEM SHALL report no
  base.
- WHEN a nested navigator pushes pages, THE SYSTEM SHALL not treat them as the
  app's page.

## Limits

- WHEN the user was in the viewer, THE SYSTEM SHALL restore the media set under
  it, not the photo.
- WHEN the user was in the explorer, THE SYSTEM SHALL reopen the configured home
  page instead of the browsed path.
- WHEN a picker or an external view had the foreground, THE SYSTEM SHALL not
  restore it.
- WHEN a snapshot is restored, THE SYSTEM SHALL not restore a scroll position, a
  map camera, a selection or a search.
