# Album contents transfer

Copies, moves, renames and scopes deletes over the contents of stored albums,
without touching entries the user cannot see.

Status: **in progress**. The move (`44f185c9c`, `1fe9d793e`), copy and scoped
delete (`b065feac5`), stored rename (`cb9094762`), whole-folder rename
(`823421366`, `88447a60c`, `dd0c6f455`) are on `avest-dev`; nothing is released.

## Scope

In scope:

- move the visible contents of one or more albums into another album;
- copy the same contents without emptying the source;
- rename a stored album, as a folder rename when the platform can, otherwise as
  a batched move;
- delete the visible contents of an album and clean up the folders that became
  empty;
- keep the visible range, hidden filters and vault rules in force.

Out of scope:

- renaming a system album or a Media Store bucket that has no stored name;
- moving a vault album's contents out of the vault;
- per-entry progress over a scope too large to materialize.

## Version facts

| Fact | Value |
| --- | --- |
| Feed | `AlbumContentsEntryFeed` (keyset pagination by id) |
| Entry limit | shared scope limit; a larger album is refused with an explanation |
| Rename strategies | `app_private`, `media_store`, `saf`, `batched` |
| Case-only rename | two-step through `.aves_renaming_<nanoTime>` |
| Cleanup | `EmptyAlbumFolderCleaner` then native `deleteEmptyDirectories` |
| Entry points | album chip set actions, album picker |

## Reading order

1. `spec.md` — what the feature must do.
2. `rules.md` — the case register.
3. `decisions/` — why rename is all-or-nothing and why a probe failure keeps the
   old behaviour.
4. `testing.md` — gates and device checks.

## Code map

| Layer | Path |
| --- | --- |
| Plans | `lib/features/album_contents_transfer/model/` |
| Services | `lib/features/album_contents_transfer/services/` |
| Actions | `lib/features/album_contents_transfer/view/` |
| Native folder rename | `android/app/src/main/kotlin/deckers/thibault/aves/storage/AlbumRename.kt` |
| Tests | `test/features/album_contents_transfer/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
