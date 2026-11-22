# Session restore

Reopens the page the user was on when Android killed the app, after a plain
launch: a top-level destination plus the collection filters that described it,
and nothing more.

Status: **in progress**. The snapshot, the route observer and the restore plan
are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- one snapshot: the restorable top page, its collection filters, the page below
  it when it is a pushed wallpaper page, and the shared-entry sub-page flag;
- save on `inactive`/`paused` in main mode, clear on back-out and on `detached`;
- restore only on a launch that carries no intent data;
- rebuild a base page before a pushed page;
- reject anything the app cannot reopen, and drop an unusable base instead of the
  page.

Out of scope:

- scroll offsets, map cameras, selections, searches, viewer entries, explorer
  paths, settings sub-pages and picker pages;
- restoring a page the user reached through another app (an intent owns that);
- more than one remembered page;
- an expiry: the lifecycle is the only clock.

## Version facts

| Fact | Value |
| --- | --- |
| Storage | one JSON string under `session_restore.snapshot` |
| Restorable routes | collection, album list, tag list, map, muzei wallpaper, visible range, grouped wallpaper |
| Pushed routes | muzei wallpaper, grouped wallpaper |
| Fields | `route`, `filters`, `baseRoute`, `baseFilters`, `rangeWallpaper` |
| Observer | root navigator only |
| Rule check | `scripts/check-session-restore-rules.ps1` |

## Reading order

1. `spec.md` — what is remembered, written, restored and refused.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the allow-list, the plan and the two integration seams.
4. `decisions/` — why one blob, why no expiry, why the base is droppable.
5. `testing.md` — fixtures and the device checklist.

## Code map

| Layer | Path |
| --- | --- |
| Snapshot and validation | `lib/features/session_restore/session_restore_snapshot.dart` |
| Store | `lib/features/session_restore/session_restore_store.dart` |
| Route allow-list | `lib/features/session_restore/session_restore_routes.dart` |
| Observer | `lib/features/session_restore/session_restore_route_observer.dart` |
| Plan | `lib/features/session_restore/session_restore_plan.dart` |
| Collection filters | `lib/features/session_restore/session_restore_collection_state.dart` |
| Lifecycle seam | `lib/widgets/aves_app.dart` |
| Restore seam | `lib/widgets/home/home_page.dart`, `lib/widgets/collection/collection_page.dart` |
| Tests | `test/features/session_restore/` |

## Privacy note

The snapshot records a route and filters, never a path or a title. See
`docs/README.md`.
