# Stacking — testing

## Host coverage

- `test/features/stacking/stack_grouping_test.dart` drives the pure policy: the
  base name, the burst key and its missing inputs, the first frame, the extension
  tie, developed-over-RAW, and the no-survivor outcome.
- `test/features/drift_db/entry_stack_test.dart` drives the write path and the
  read-back: settling a tile, a pattern rebuild, moves and deletes, the member
  order of a developed stack and the lone-row guard.
- `test/features/collection_paging/paged_stack_test.dart` covers the presentation
  half and is registered in `collection_paging` (`LEN-28`, `LEN-29`): one tile per
  burst, a RAW returning when its tile is filtered out or binned, and the calendar
  layout.
- `test/features/drift_db/migration_v4_test.dart` and
  `entry_directory_rename_test.dart` cover the backfill and the rename.

The policy tests register a POSIX `p.Context` because the base-name helper comes
from GetIt; the DB tests use an in-memory Drift database and the shared SQLite
loader.

## Device checks

- A burst from the camera album shows one tile with a count badge; opening it pages
  through the frames in name order.
- A RAW+JPEG pair shows the JPEG; deleting it makes the RAW reappear.
- Changing the burst patterns in settings re-folds the library without reopening
  the collection.

The badge and the viewer paging are layout; `AGENTS.md` exempts widgets from host
tests.

## Discipline

- A policy change starts in `stack_grouping_test.dart`; the DB and paging tests
  only prove that the policy is applied.
- A new comparison rule updates `compareNames` and the presentation ordering
  together: the viewer and the tile must agree.
- A schema change to the stack columns is a migration (`drift_db`), never a
  derived-at-read workaround.
