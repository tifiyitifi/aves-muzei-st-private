# Collection paging — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## Choosing the load path

- WHEN the engine is `auto` and the library is at or above the threshold, THE
  SYSTEM SHALL page the view.
- WHEN the engine is `auto` and the library is below the threshold, THE SYSTEM
  SHALL keep the legacy in-memory path.
- WHEN the user selects legacy, THE SYSTEM SHALL use the legacy path even above
  the threshold.
- WHEN the user selects paged, THE SYSTEM SHALL page even a small collection.
- WHEN a filter cannot be expressed in SQL, THE SYSTEM SHALL keep the legacy path
  for that view.
- WHEN the library is still being imported, THE SYSTEM SHALL never fully load it.
- WHEN the size probe fails or cannot prove the library small, THE SYSTEM SHALL
  keep the legacy path rather than risk a full load.
- WHEN the SQL predicate is available, THE SYSTEM SHALL keep it on a legacy
  decision, so a too-large library can still serve the scope windowed.
- WHEN a vault is locked, THE SYSTEM SHALL page it and keep its rows hidden.
- WHEN hidden filters exist, THE SYSTEM SHALL compile them into the predicate.
- WHEN the routing answer is computed, THE SYSTEM SHALL answer for the library,
  not only for the requested scope.

## Preferences

- WHEN no value is stored, THE SYSTEM SHALL use `auto`, a 200-entry window, two
  prefetch screens and the smallest large threshold.
- WHEN a stored engine name is unknown, THE SYSTEM SHALL reject it and fall back
  to the default.
- WHEN a window size or threshold is persisted, THE SYSTEM SHALL clamp it into
  its allowed range.
- WHEN a persisted value is unreadable, THE SYSTEM SHALL fall back to defaults.
- WHEN the import completes, THE SYSTEM SHALL record it in memory before touching
  the preference store.
- WHEN a value does not change, THE SYSTEM SHALL not notify listeners.

## First import

- WHEN the first batch is written, THE SYSTEM SHALL paint the view before the
  rest of the library lands.
- WHEN the import finishes, THE SYSTEM SHALL settle the view out of loading.
- WHEN an import fails before its first batch, THE SYSTEM SHALL not resolve the
  view as ready.
- WHEN an import outlives its lens, THE SYSTEM SHALL still end the shared import
  status.
- WHEN the stream goes silent, THE SYSTEM SHALL fail the import instead of
  hanging.
- WHEN rows repeat in one batch or share a content id, THE SYSTEM SHALL keep one
  row per identity.
- WHEN a row reports no content id, THE SYSTEM SHALL still import it.
- WHEN the import stops mid-stream, THE SYSTEM SHALL resume from the stored
  cursor.

## Change-based sync

- WHEN the MediaStore generation is unchanged, THE SYSTEM SHALL do nothing.
- WHEN the generation is unknown, THE SYSTEM SHALL baseline it without
  backfilling.
- WHEN the generation moves, THE SYSTEM SHALL fetch only the changed URIs.
- WHEN a change fails transiently, THE SYSTEM SHALL keep it in a retry list and
  write that list before advancing the cursor.
- WHEN a changed file has no content id, THE SYSTEM SHALL match it by URI instead
  of inserting a duplicate.
- WHEN an obsolete file is found, THE SYSTEM SHALL remove its row, settling the
  whole change set in one check.
- WHEN a provider stops reporting an id, THE SYSTEM SHALL keep the stored id.
- WHEN a row's id now names another file, THE SYSTEM SHALL remove the stale row.
- WHEN a burst of platform events arrives, THE SYSTEM SHALL coalesce it into one
  sync and publish once.
- WHEN a sync fails, THE SYSTEM SHALL swallow the error rather than break
  browsing.
- WHEN an import runs, THE SYSTEM SHALL let it own discovery and leave the
  browser alone.
- WHEN a media operation is in flight, THE SYSTEM SHALL wait for it to settle.
- WHEN a sweep would drop most of the library, THE SYSTEM SHALL refuse it.
- WHEN a volume is unmounted, THE SYSTEM SHALL not ask about it.

## Background catalogue

- WHEN a large backlog is found, THE SYSTEM SHALL raise the catalogue prompt
  once per session.
- WHEN the user opted out, THE SYSTEM SHALL not ask.
- WHEN the user chooses catalogue now, THE SYSTEM SHALL sweep the backlog and
  keep asking later.
- WHEN the user chooses later, THE SYSTEM SHALL sweep nothing.
- WHEN the user chooses always, THE SYSTEM SHALL sweep and stop asking, until the
  choice is reset.
- WHEN a backlog outlasts a visit and the system service is available, THE SYSTEM
  SHALL delegate it; otherwise THE SYSTEM SHALL keep it in the app.
- WHEN the app sweeps, THE SYSTEM SHALL do it in chunks, view scope first, and
  notify progress.
- WHEN a pass is interrupted, THE SYSTEM SHALL resume from the saved frontier.
- WHEN an entry is poisoned, THE SYSTEM SHALL skip it and keep going.
- WHEN the sweep reaches unlocated GPS rows, THE SYSTEM SHALL locate their
  countries when locating is available.

## Summaries, selection and views

- WHEN a summary is read before loading, THE SYSTEM SHALL return empty rather
  than block.
- WHEN an entry-free source is published, THE SYSTEM SHALL serve summaries from
  the database provider.
- WHEN a source holds entries, THE SYSTEM SHALL keep its in-memory summaries
  authoritative.
- WHEN a page opens without a lens, THE SYSTEM SHALL attach the database provider
  so the album list is not empty.
- WHEN a selection covers a scope larger than memory, THE SYSTEM SHALL use a
  declared feed and SHALL refuse to materialize past the limit.
- WHEN a mark has traits and manual layers, THE SYSTEM SHALL let the last
  covering op decide, with a manual tap piercing every trait.
- WHEN a section header is turned into a trait, THE SYSTEM SHALL cover the whole
  section, not the loaded rows.
- WHEN a viewer copy is asked for a position, THE SYSTEM SHALL resolve it across
  windows, keeping shuffle inverse to the global index.
- WHEN a slideshow opens, THE SYSTEM SHALL keep a window-backed, seeded
  permutation rather than a snapshot.
- WHEN a scope is revisited, THE SYSTEM SHALL reuse its lens and filters.
- WHEN the browse-only mode is on, THE SYSTEM SHALL lock writes and bulk actions
  until the import ends.
- WHEN an action cannot be served over a paged library, THE SYSTEM SHALL report
  it instead of acting on an empty in-memory source.
- WHEN the user appends a selection to the media set, THE SYSTEM SHALL merge it
  with the set currently in scope, fold album conditions into one deduplicated
  union and keep every other condition.
- WHEN a borrowed view owns the media set, THE SYSTEM SHALL append to that set
  instead of the app-wide slot.

## Counts

- WHEN stats are grouped, THE SYSTEM SHALL read the catalogued metadata when it
  exists and the entry otherwise.
- WHEN a range is short, medium or long, THE SYSTEM SHALL bucket by day, month or
  year.
- WHEN the library is large, THE SYSTEM SHALL stream the stats instead of
  aggregating in memory.
- WHEN the export stream is read, THE SYSTEM SHALL include every row of the
  scope with its metadata.

## The library phase

- WHEN the library is not whole, THE SYSTEM SHALL keep browsing.
- WHEN the library becomes whole, THE SYSTEM SHALL never return to browsing, even
  for a late run or new rows.
- WHEN the database is reset, THE SYSTEM SHALL browse again while it is read
  back.
- WHEN the import fails, THE SYSTEM SHALL keep browsing and clear the phase only
  on a retry.

## Platform calls

- WHEN a platform step answers, THE SYSTEM SHALL pass its value through.
- WHEN a platform step never answers, THE SYSTEM SHALL bound the wait and read it
  as missing.
- WHEN a platform step fails, THE SYSTEM SHALL report it instead of throwing it
  at the resolve.
