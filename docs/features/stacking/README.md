# Stacking

What a stack is: which rows share a burst key, which member is the tile, which
members hide behind it, and in what order the members are presented.

Status: **in progress**. The policy, the persisted index and the paged wiring are
on `avest-dev`; nothing is released yet.

## Scope

In scope:

- the burst key: `<directory>/<base name without extension>` when a configured
  burst pattern matches;
- the representative: the first member by natural base-name order, ties by
  extension;
- the keyless rule: a RAW hides when a developed image of the same directory and
  base name exists;
- the "nothing hides" outcome when a group has no single survivor;
- presentation order: burst members by the same natural comparison, a developed
  image before its RAW.

Out of scope (owned by other registers):

- how a member is hidden in a paged window and what a filter does to a tile —
  `docs/features/collection_paging/rules.md` `LEN-28`, `LEN-29`;
- settling the persisted `stackTileId` on write, deletes and re-homes —
  `docs/features/drift_db/rules.md` `QRY-6`;
- the directory rename and the v4 backfill — `QRY-8`, `MIG-3`.

## Version facts

| Fact | Value |
| --- | --- |
| Key | `<directory>/<burst key>` |
| Representative | first by `compareAsciiUpperCaseNatural(baseName)`, then extension |
| Keyless pair | RAW hidden behind a developed image of the same base name |
| Persisted columns | `baseName`, `stackKey`, `stackTileId` (schema v4) |
| Patterns | `Settings.collectionBurstPatterns` |
| Rule check | `scripts/check-stacking-rules.ps1` |

## Reading order

1. `spec.md` — what a stack is, as behaviour.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — the two passes, the representative rule and the boundaries.
4. `decisions/` — why base name, why natural ASCII order, why all-null groups.
5. `testing.md` — the fixtures and the cross-slice tests.

## Code map

| Layer | Path |
| --- | --- |
| Policy | `lib/features/stacking/model/stack_grouping.dart` |
| Persisted index | `lib/features/drift_db/entries/entry_table.dart`, `entry_store.dart` |
| Paged presentation | `lib/features/collection_paging/lens/paged_collection_lens.dart` |
| Legacy parity | `lib/model/source/collection_lens.dart` |
| Tests | `test/features/stacking/`, `test/features/drift_db/entry_stack_test.dart`, `test/features/collection_paging/paged_stack_test.dart` |

## Privacy note

Fixtures use stand-in camera paths and numbered frames. See `docs/README.md`.
