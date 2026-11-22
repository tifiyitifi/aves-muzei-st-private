# Collection paging — design

## The database is the library

```
MediaStore ──import/sync──► Drift entries ──window cache──► paged lens ──► view
                                   │
                                   ├── summaries (albums, tags, places)
                                   ├── stats (counts, ratings, dates)
                                   └── selection feeds (traits, marks)
```

An entry-free `CollectionSource` is the paged source: it holds no entries, and
the database answers every question the legacy source answered from memory. Two
seams keep that honest:

- `CollectionSource.isPaged` (or an attached summary provider) tells callers the
  database is authoritative;
- `PagedScopeGuard` stops an action that would read the in-memory source from
  acting on an empty list.

The album list is the clearest consequence: a page reached without a lens (the
album destination, a wallpaper pick) has no provider attached, so
`ensureAlbumList` attaches the database provider before answering. A fully
loaded source is left alone, because switching it to the database behind a
legacy view would make counts disagree with the rows on screen.

## The engine decision is per view

`CollectionEngineRouter.decide` returns a route plus, when SQL can express the
scope, the predicate and the total. The order of checks matters:

1. the current MediaStore generation is being imported → legacy (never fully load
   a half-filled database);
2. the SQL predicate cannot be built → legacy;
3. the engine is explicitly `legacy` → legacy;
4. `paged` → paged;
5. `auto`: page at or above the threshold, legacy below it.

A probe failure keeps legacy: a wrong "small" guess would materialize the
library. A legacy decision still carries its predicate, so a below-threshold
scope inside a too-large library can be served windowed when the full load turns
out unsafe.

A vault contributes a negated directory subtree to the predicate; its rows stay
in the database and never reach a window.

## Windows never block

`WindowCache` is a window-aligned LRU over an async row source:

- `peek` answers from memory or null, so a frame never waits;
- `ensure` fetches the missed window plus bounded neighbours;
- rapid misses coalesce into one batch around the fling's destination;
- `invalidate` bumps a generation; a completion from an older generation is
  dropped, so a stale fetch cannot splice rows from another scope;
- fills and evictions are reported so owners can mirror the cache and stay
  bounded.

The lens keeps the total, the scope identity and the window cache. Scrolling is a
series of `peek`/`ensure` calls; a lookup (`entryAt`) materializes one row when it
is outside the loaded windows, which is what the viewer needs.

## First import is resumable

`PagedDiscoverer.importAll` streams every MediaStore row once, upserts per chunk
by content id, signals the first batch, and skips rows already stored. The view
paints after that signal; the remaining chunks stream behind it. The completion
flag (`import_complete`) is what moves `LibraryPhase` to `ready`; a reset
database clears the flag and browses again while it is read back.

Repeated rows in one batch are merged under their identities: an image and a
video may share a content id, and a row may report no id at all.

## Sync is generation-gated

`syncIfChanged` reads one cheap platform generation query. When it is unchanged,
nothing happens. When it moves, only the changed URIs are fetched, and the
vanished ones are settled by one obsolete check for the whole set. Failures go
to `pending_sync_uris`, which is written before the cursor advances — otherwise
the new cursor would hide the failed change forever.

The obsolete sweep has a guard: a sweep that would drop most of the library is
refused, and an unmounted volume is never asked about.

A burst of platform events is debounced into one sync and published once. During
an import, discovery belongs to the import; the browser is not told.

## The catalogue is backlog work, not a gate

New rows are catalogued inline on sync, so the catalogue is the part of an
existing library that has not been reached yet. The prompt asks once per session,
only for a backlog worth mentioning, and offers three answers. A backlog too
large to finish during a visit is handed to the system analysis service; a small
one runs in the app worker, view scope first, in chunks, resuming from the saved
frontier. A poisoned entry is skipped rather than ending the pass.

Progress is a session object: it takes the total and the clock, estimates from a
rolling rate, never rewinds, and lets only the current owner update or finish it.

## Selection over a scope larger than memory

A materialized feed hands its set over whole; a declared feed walks the scope in
bounded batches and refuses to materialize past the limit. A mark combines trait
operations with manual layers: the last op covering a row decides, a manual tap
pierces every trait, and a manual drop wins over a trait that selects the row.
Section headers become exact traits over the whole section, not over the loaded
rows.

## Views

- **Viewer copy** resolves positions through its parent lens across windows, and
  keeps shuffle inverse to the global index.
- **Slideshow** freezes a seeded permutation plus the total at open time, so a
  changing collection does not perturb the running order.
- **Stacks** group a burst into one tile; a RAW sibling shows when its developed
  tile is filtered out or binned.
- **Widget candidates** read the first row of the order or one row through the
  permutation, keeping the legacy path below the threshold.
- **Media set tab** remembers the album the slot showed; the bin never writes it.
- **Browse-only mode** locks writes and bulk actions while the import runs and
  unlocks as soon as it ends.

## Anti-patterns

- **Reading `source.visibleEntries` in a paged view.** It is empty by design; ask
  the lens, the database or a feed.
- **A blocking `await` on a first window in `build`.** Windows are peeked; a miss
  schedules a fetch.
- **Advancing the sync cursor before persisting the retry list.** The failed
  change is lost.
- **Judging a sweep by the current view.** The guard compares against the whole
  library, or a filter switch looks like mass deletion.
- **Recording the import flag before the import ends.** A later launch would skip
  the rest of the library.
- **Leaving the phase to a per-lens flag.** Multiple signals disagree for a
  frame, which is enough to flicker between browsing and the collection.
