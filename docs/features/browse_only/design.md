# Browse only — design

## Why a separate surface

The collection is the database. While the import is still writing it, every reader
of the database answers from a partial state: a folder list missing most albums, a
timeline missing most days, counts that grow between two frames. Every attempt to
make the collection answer earlier leaked half-built answers into the UI, so the
browser answers from MediaStore instead and is not the collection with filters
applied.

## Data flow

```text
MediaStore (BrowseMediaStore.fetchPage)
  -> mediaStoreService.getMediaPage(limit, before, directory)
  -> BrowseLibrary: List<BrowseRow> + uri -> index, cursor, token, LRU entries
  -> mediaIndexes(sort, reverse, videosOnly)   (display order, cached)
  -> BrowseMediaGrid -> browseGridItems(...)     (month header + rows of tiles)
  -> browseViewerLens(source, entries)            (detached, fixedSelection)
  -> viewer
```

Albums:

```text
mediaStoreService.getAlbumSummaries()
  -> BrowseAlbums: all folders + counts + covers, filtered by hidden albums
  -> BrowseAlbumsView (grid)  --tap-->  BrowseAlbumPage
                                          -> BrowseAlbumLoader
                                             -> BrowseLibrary(directory)
                                             -> loadAll()
```

## The window

- `pageSize = 250`, `previewRowLimit = 5000`, page timeout 15 s, entry cache 600.
- `rowLimit` is `null` for an album window (read the folder whole) and the preview
  limit for the global timeline.
- The cursor is a platform object (`MediaStorePageCursor` with one key per
  collection), because only the platform knows how many rows it filtered out of a
  page. An empty page with more rows is read past; a cursor that does not advance
  is an error.
- A token invalidates in-flight pages on `clear`/`dispose`. Clearing during the
  first read counts as "had content" so the view is told to drop its spinner.
- A failure keeps the rows and stops auto-paging; retry resumes from the last
  cursor.
- Rows are deduped by URI (images and videos have independent id spaces) and
  trashed rows are dropped.
- The index is a light `BrowseRow` list; an `AvesEntry` is materialized on demand
  with a negative synthetic id, so it can never alias a real database row in a
  viewer or a selection keyed by id.
- The viewer gets a bounded window in a lens that does not follow the source
  (`browseViewerLens`): its rows are the media store's, so an import event must not
  grow, shrink or reorder the set under the user's swipe.

## Order and sections

`mediaIndexes` returns the display order, cached by key plus a version counter.
Date sort compares `bestDateMillis` (capture, then modified, then added, with zero
meaning "unknown" — not 1970), breaking ties by the later index so the newest read
wins. Name sort compares lowercased titles, then date, then index.

Month headers are ordinary list items, not pinned slivers: a rigid pinned header
never shrinks, so sections stack until the screen is headers. `browseGridItems`
flattens the order into `[month, rows...]` with at most `columns` tiles per row and
never mixes two months in one row.

The scroller is arithmetic over the item list (`BrowseScrollMap`): month starts
accumulate header and row extents plus bottom padding; `monthAt` binary-searches
and clamps; `snap` picks the nearer start. It appears only from four months.

## The chrome

The title names the view after the user's own navigation item (`viewFor`), falling
back to the built-in tab name when the bar has no entry for it: the bar and the
title cannot drift apart.

The timeline has three states before it has rows: progress while the first read is
in flight, the failure with its retry when nothing was read, and the empty library
otherwise. The preview strip appears when the window is at its limit or its last
page failed; its action continues past the limit or retries the failed page.

The strip states the **displayed** row count (`order.length`), because hidden
albums are read but not rendered, while the read budget itself stays on the raw
count in `atLimit` (decision `0006`).

## The album list

One aggregate read returns every folder with its count, cover and newest date; the
list is replaced as a whole so a count is never seen growing. Hidden albums are
filtered at derive time, so a settings change lands on the loaded list without a
re-scan. Same-named folders are labelled with their parent. The album page reads
its folder whole through its own window (`rowLimit == null`), keeps the rows it
got when the tail fails, and retries the rest.

## The bar and the drawer

The bottom bar renders the user's `bottomNavigationActions` verbatim, appending the
visible-range destination once. A `viewFor` mapping turns a collection destination
into the timeline and the album list into the albums; anything else is dimmed with
no ink response and no tap handler, so it cannot fake a working entry.

The drawer uses a fail-closed whitelist: organized means everything is enabled;
browsing enables the timeline, the album list, the explorer and the app pages, and
greys anything narrowed by catalogued metadata or unnamed by the whitelist.

## Anti-patterns

- Feeding the browser from the import's row stream: it would grow one row at a time
  and reproduce the half-built answers.
- Answering browsing from the collection or the lens.
- Merging images and videos into one cursor or content-id key.
- A fixed bar, or rewriting the user's bar: it was tried and reverted.
- Pinned month slivers.
- Materializing the whole index for the viewer.
- Writing the notice strip into an app bar once: the handoff can happen while the
  page is on screen.
- Clearing the browser on `BrowseOnlyPage.dispose` instead of on the phase change:
  the page can be rebuilt without the phase changing.
