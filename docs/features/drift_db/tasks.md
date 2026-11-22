# Drift database — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| A schema snapshot test (dump `sqlite_master` and compare) | catches an accidental column rename that the per-step tests do not assert | `GEN-1` |
| A script that lists migrations without a test file | the register check proves a cited test exists, not that every `MigrationVN` has one | `MIG-1`..`MIG-17` |
| A note on the expected size of `aves.drift.db` and when to run `VACUUM` | the database grows with the catalog and is never compacted | `DB-5` |
| Decide whether `debug` rows should be pruned on a schedule | the table is append-only today | `DB-8` |

Not planned: a second database for feature tables. The single `@DriftDatabase`
is what lets a query join the catalog with a range or a batch row.
