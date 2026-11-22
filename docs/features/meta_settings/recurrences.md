# Metadata settings engine — what comes back

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | After switching engines, the settings page shows the new values but the app behaves with the old ones | The listeners that cache brightness, refresh rate, layout or locale read the previous store and were never notified | `INIT-4`, `INIT-5`, `INIT-6` | A switch activates the store without replaying the diff, or replays with `recordRecent: true` | implementation, 2026 |
| R2 | An upgrading user opens v2 and every setting is back at its default | The seed did not run, or its marker was written before the copy finished | `SEED-1`, `SEED-4`, `SEED-6` | The marker is written unconditionally, or v2 init skips the seeder | implementation, 2026 |
| R3 | The engine choice changes by itself after a settings reset or an export/import | The gate is read through the settings key space or written by a caller | `GATE-3`, `GATE-4`, `GATE-5` | The gate key leaks into `getKeys`, `remove` or the active store's writes | implementation, 2026 |
| R4 | A setting silently reverts a moment after being toggled | The optimistic value was applied by a listener, then the write failed and the cache re-synced without re-emitting | `STORE-4`, `STORE-6` | The store re-emits on re-sync, or a caller ignores `flush()` on a batch path | `MetaSettingsStore` doc comment |
| R5 | A category shows fewer settings than the legacy page | A def was removed or a category was declared migrated early | `CAT-3`, `CAT-4`, `CAT-9` | A def is deleted instead of superseded, or a category list is trimmed | implementation, 2026 |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | A setting key | catalog defs, typed getters, seeder, search keys | Add or move a key only with its compile-checked `SettingKeys` constant; update the def, the reader and the search-key entry together | `catalog.dart`, `def_search_keys.dart` |
| C2 | The gate value | router, controller, legacy store file | Never read or write it through `settings`; use `SettingsEngineGate` | `settings_store_router.dart` |
| C3 | The seed marker | seeder, router init, v2 clear | Write it only after a complete pass; never clear it as part of a settings reset | `meta_settings_seeder.dart` |
| C4 | The store's value type | DAO tag, codec, guard, typed getter | One key has one type; a type change needs a migration, not a coercing reader | `settings_dao.dart`, `value_codec.dart` |
