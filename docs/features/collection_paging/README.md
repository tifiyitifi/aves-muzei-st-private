# Collection paging

Loads a collection from the database window by window instead of materializing
it, so a library of hundreds of thousands of entries opens, scrolls and filters
without loading everything into memory. Small libraries keep the upstream
in-memory path.

Status: **in progress**. The engine, the first import, change-based sync, the
background catalogue, summaries, selection feeds and the paged views are on
`avest-dev`; nothing is released yet.

## Scope

In scope:

- choosing the load path per view: legacy, paged, or automatic by library size;
- a chunked, resumable first import that paints after its first batch;
- a bounded window cache with prefetch, coalescing and generation-safe fills;
- MediaStore to database sync by generation, plus an obsolete-row sweep;
- a background catalogue with a one-per-session prompt and a system service for
  backlogs too large to finish in-app;
- album/tag/location summaries served by the database, not by loaded entries;
- selection feeds and section traits over a scope larger than memory;
- viewer copies, shuffle, slideshow, stack grouping and widget candidates over
  windows;
- the browse-only mode shown while the first import runs.

Out of scope:

- changing the upstream `LocalMediaDb` interface (the fork implements it);
- the visible-range expression itself (see `docs/features/visible_range/`);
- cloud or network libraries.

## Version facts

| Fact | Value |
| --- | --- |
| Engine values | `legacy`, `paged`, `auto` (default `auto`) |
| Preference keys | `collection_paging.*` in `SharedPreferences` |
| Default window | 200 (`maxWindowSize` 1000) |
| Default prefetch | 2 screens (max 3) |
| Default large threshold | 20 000 (max 10 000 000) |
| Import flag | `collection_paging.import_complete` |
| Sync cursor | `collection_paging.media_generation` + `pending_sync_uris` |
| Rule check | `scripts/check-collection-paging-rules.ps1` |

## Reading order

1. `spec.md` — what a paged collection must do.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the engine decision, the windows, the import and the catalogue.
4. `decisions/` — why the database is the library, why windows never block, why
   the phase only moves forward.
5. `testing.md` — gates, fixtures, the sqlite requirement and the device checks.

## Code map

| Layer | Path |
| --- | --- |
| Engine decision | `lib/features/collection_paging/engine/` |
| Lens and scope | `lib/features/collection_paging/lens/` |
| SQL predicate and cache keys | `lib/features/collection_paging/query/` |
| MediaStore sync | `lib/features/collection_paging/sync/` |
| Background catalogue | `lib/features/collection_paging/catalog/` |
| Summaries | `lib/features/collection_paging/summary/` |
| Selection feeds and traits | `lib/features/collection_paging/selection/` |
| Stats | `lib/features/collection_paging/stats/` |
| Window cache | `lib/features/collection_paging/windows/` |
| Views | `lib/features/collection_paging/view/` |
| Tests | `test/features/collection_paging/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
