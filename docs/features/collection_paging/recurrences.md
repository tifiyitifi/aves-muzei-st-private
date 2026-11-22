# Collection paging — what comes back

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | The album list flashes to "no albums", or the grid swaps to the browse-only browser and back | Several signals (a per-lens flag, the import status, a preference) disagreed for a frame | `PHS-1`, `PHS-2`, `LEN-19` | A surface answers "is the library whole" from its own state instead of `LibraryPhase` | implementation, 2026 |
| R2 | Re-running the import doubles the library | The import matched rows by path or inserted without an identity | `IMP-8`, `IMP-9`, `SYN-7` | The identity merge is bypassed for rows without a content id | implementation, 2026 |
| R3 | After switching scope, the grid shows rows from the previous one | A window fill from an older generation was spliced into the new cache | `SYN-1`, `LEN-17`, `LEN-18` | `invalidate` stops bumping the generation, or a fill ignores it | implementation, 2026 |
| R4 | A page reached without a lens shows an empty album list | The source was entry-free and no summary provider was attached | `SUM-5`, `SUM-6` | `ensureAlbumList` stops attaching the provider | implementation, 2026 |
| R5 | After a crash the library is missing its older half, and no import runs | The completion flag was written before the import ended | `PHS-5`, `PHS-6`, `IMP-15` | Completion is recorded on the first batch instead of the last | implementation, 2026 |
| R6 | The catalogue prompt appears on every launch, or never | The session answer or the opt-out was not read | `CAT-1`, `CAT-2`, `CAT-3` | The prompt state moves into a rebuilt controller | implementation, 2026 |
| R7 | Scrolling a huge album stutters and memory climbs | The view walks the lazy list or materializes windows ahead without a bound | `LEN-5`, `LEN-33`, `SEL-9` | A caller iterates `lens.entries` instead of the loaded rows | implementation, 2026 |
| R8 | A bulk action over a paged library silently does nothing | The action read the in-memory source, which is empty by design | `LEN-36`, `LEN-33` | `pagedScopeUnsupported` is dropped from an action | implementation, 2026 |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | The MediaStore generation cursor | sync, import, resume, sweep | Advance it only after the retry list and the changed rows are persisted | `collection_paging_keys.dart`, `paged_sync.dart` |
| C2 | `import_complete` / `LibraryPhase` | router, lens, browse-only mode, views | Move the phase in one place and one direction | `library_phase.dart` |
| C3 | A window index and generation | `WindowCache`, lens, viewer copy | Drop fills from an older generation; never renumber windows in place | `window_cache.dart` |
| C4 | A scope's canonical filters | scope registry, lens, media-set slot | Key by the filter set, not the route or the order | `scope_registry.dart` |
| C5 | The entry identity (content id, URI, id) | import, sync, selection, viewer copy | Decide it once; a new path must reuse the same merge | `paged_sync.dart`, `entry_id_allocator.dart` |
| C6 | The summary provider | album list, tags, places, filter grids | A page that reads the database must attach it before answering | `ensure_album_list.dart`, `paged_scope_guard.dart` |
