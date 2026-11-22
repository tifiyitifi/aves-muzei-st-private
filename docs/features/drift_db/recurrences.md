# Drift database — what comes back

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | An upgrade crashes with "duplicate column" or "table already exists" | A step added a column a later step already created through the current table definition | `MIG-6`..`MIG-14` | A migration stops guarding its structural change | implementation, 2026 |
| R2 | A new build opens an old database with a missing column or table | The version was bumped without a migration, or the generated schema was not regenerated | `MIG-1`..`MIG-17`, `GEN-1` | `schemaVersion` changes without `MigrationVN` + test, or the `.g.dart` is stale | `AGENTS.md` |
| R3 | The library doubles after an upgrade | The legacy import ran twice, or matched rows by path instead of identity | `LEG-1`, `DB-6` | The import marker is skipped, or the identity merge is bypassed | implementation, 2026 |
| R4 | A range or group loses its narrowing after the schema change | A rebuild copied rows without preserving the effective value | `MIG-12`, `MIG-13` | A table rebuild drops the surface or the folded base | implementation, 2026 |
| R5 | Settings are missing right after the first launch | v2 settings opened a second connection before the provider existed, or the import ran first | `DB-1`, `MIG-1` | Settings init stops going through the provider | implementation, 2026 |
| R6 | A large upgrade is killed and never finishes | The import committed rows without a cursor, or a corrupt cursor was trusted | `LEG-3`, `LEG-7` | Cursor and chunk commits are reordered | implementation, 2026 |
| R7 | The app reads rows the grid does not show | A summary query forgot the trash/hidden/vault exclusion | `QRY-7` | A new summary path re-derives the predicate | implementation, 2026 |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | `schemaVersion` | every migration, `onCreate`, the generated schema | Bump it only with `MigrationVN`, a test and regenerated code | `app_database.dart` |
| C2 | A column name | queries, legacy import, generated companion classes | Keep the upstream camelCase name; renaming needs a migration | `entry_table.dart` |
| C3 | `appMeta` markers | import, seeders, sync cursor, interval catalog | Never clear a marker as part of a settings reset | `app_meta_table.dart` |
| C4 | The legacy `metadata.db` | import, backup, verification | Read-only after the import; never write it | `legacy_import.dart` |
| C5 | The provider's connection | `DriftLocalMediaDb`, `MetaSettingsStore`, features | One instance per isolate; never open a second `NativeDatabase` | `app_database_provider.dart` |
