# Browse only — requirements

## Placement

- WHEN the library phase is importing or failed and no pick is in progress, THE
  SYSTEM SHALL render the browse-only page in place of the collection grid.
- WHEN the app is in a pick mode, THE SYSTEM SHALL keep the collection grid as the
  library surface.
- WHEN the library phase reaches ready, THE SYSTEM SHALL drop the browse window and
  the browse album list.
- WHEN the drawer's album entry is opened while browsing, THE SYSTEM SHALL show the
  browse album list.
- WHEN the browse page is mounted under a scaffold that owns a drawer, THE SYSTEM
  SHALL offer a menu button that opens it.

## The paged window

- WHEN the timeline reads its first page, THE SYSTEM SHALL request at most 250 rows
  with no cursor.
- WHEN a later page is read, THE SYSTEM SHALL resume from the cursor the platform
  reported for the previous page.
- WHEN a page repeats a row the window already holds, THE SYSTEM SHALL ignore it.
- WHEN a page carries a trashed row, THE SYSTEM SHALL leave it out.
- WHEN a page is empty but more rows remain, THE SYSTEM SHALL read on with that
  page's cursor.
- WHEN a page's cursor cannot advance, THE SYSTEM SHALL stop with an error instead
  of asking again.
- WHEN a page read fails, THE SYSTEM SHALL keep the rows already read and stop
  paging on its own.
- WHEN the user retries a failed page, THE SYSTEM SHALL clear the error and resume
  from the last cursor.
- WHEN a page read stays unanswered past its timeout, THE SYSTEM SHALL report a
  timeout.
- WHEN the window reaches its preview limit, THE SYSTEM SHALL stop until the user
  asks for more.
- WHEN the user asks for more past the limit, THE SYSTEM SHALL keep loading.
- WHEN the grid comes within its paging threshold of the end, THE SYSTEM SHALL
  request one more page.
- WHEN the window is cleared while a page is in flight, THE SYSTEM SHALL discard
  that page.
- WHEN the window is cleared during its first read, THE SYSTEM SHALL notify its
  listeners.
- WHEN the library is empty, THE SYSTEM SHALL report an empty window, not an error.
- WHEN a full page returns exactly a multiple of the page size, THE SYSTEM SHALL
  confirm the end with one further read.

## Order and sections

- WHEN the timeline is sorted by date, THE SYSTEM SHALL order by best date, newest
  first unless reversed, breaking ties by the later row.
- WHEN the timeline is sorted by name, THE SYSTEM SHALL compare lowercased titles,
  then date, then index.
- WHEN rows are ordered for display, THE SYSTEM SHALL leave out hidden albums.
- WHEN the timeline is sectioned, THE SYSTEM SHALL emit a month header followed by
  rows of at most the column count.
- WHEN a row of tiles is built, THE SYSTEM SHALL not mix two months in it.
- WHEN the items are flattened, THE SYSTEM SHALL place every position exactly once.

## Timeline scroller

- WHEN the sectioned timeline has fewer than four months, THE SYSTEM SHALL not
  show the drag handle.
- WHEN a drag lands between two month starts, THE SYSTEM SHALL snap to the nearer
  start.
- WHEN the handle rests at an offset, THE SYSTEM SHALL name the month at that
  offset.
- WHEN the item list is empty, THE SYSTEM SHALL report no months and no fractions.

## Albums

- WHEN the album view mounts, THE SYSTEM SHALL read the whole folder list in one
  aggregate read.
- WHEN the list is already loaded, THE SYSTEM SHALL not read it again.
- WHEN the hidden-album set changes, THE SYSTEM SHALL re-derive the visible list
  without re-reading the media store.
- WHEN two visible folders share a name, THE SYSTEM SHALL label each with its
  parent folder.
- WHEN albums are sorted by date, name or count, THE SYSTEM SHALL honour the chosen
  direction.
- WHEN the aggregate read fails, THE SYSTEM SHALL report it with a retry instead of
  claiming there are no folders.
- WHEN the user opens a folder, THE SYSTEM SHALL read that folder alone, whole.
- WHEN a folder's read fails after some rows arrived, THE SYSTEM SHALL keep those
  rows and offer a retry.

## Navigation

- WHEN the user's navigation declares at least two items, THE SYSTEM SHALL render
  them in the user's order with the user's labels.
- WHEN the page renders its title, THE SYSTEM SHALL name the current view after the
  user's navigation item that owns it, and SHALL fall back to the built-in name
  when no item does.
- WHEN the visible-range destination is not already configured, THE SYSTEM SHALL
  append it once.
- WHEN a bar entry points at the media set or the album list, THE SYSTEM SHALL
  switch to that view.
- WHEN a bar entry needs catalogued metadata, THE SYSTEM SHALL keep it visible,
  dimmed, and without a tap handler.
- WHEN the library is organized, THE SYSTEM SHALL enable every drawer entry.
- WHILE browsing, THE SYSTEM SHALL enable the timeline, the album list, the explorer
  and the app pages, and SHALL grey anything narrowed by catalogued metadata.
- WHILE browsing, THE SYSTEM SHALL grey a destination its whitelist does not name.

## Viewer and states

- WHEN a tile is tapped, THE SYSTEM SHALL open the viewer at that position with at
  most 250 neighbours on each side in display order.
- WHEN the tapped position is outside the displayed order, THE SYSTEM SHALL not
  open the viewer.
- WHEN a tile is rendered in the browser, THE SYSTEM SHALL not make it selectable.
- WHEN the first page is in flight and nothing is read, THE SYSTEM SHALL show
  progress.
- WHEN the first page failed and nothing was read, THE SYSTEM SHALL show the
  failure with a retry.
- WHEN a view is empty while an import runs, THE SYSTEM SHALL say the library is
  being imported.
- WHEN the timeline reached its limit or its last page failed, THE SYSTEM SHALL show
  the preview strip.
- WHEN the preview strip states how many rows the timeline shows, THE SYSTEM SHALL
  count the displayed rows, not the rows the window read.

## Preferences

- WHEN a browse sort is picked, THE SYSTEM SHALL persist it under the
  `browse_only.*` keys.
- WHEN a browse preference cannot be read, THE SYSTEM SHALL keep the built-in
  default.
- WHEN the browse page opens, THE SYSTEM SHALL load the persisted sort.
- WHEN the browse sort changes, THE SYSTEM SHALL leave the collection's own sort
  settings untouched.

## Non-goals

- WHEN an action needs the catalogued database, THE SYSTEM SHALL not emulate it in
  the browser.
- WHEN a picker is open, THE SYSTEM SHALL never show the browser.
