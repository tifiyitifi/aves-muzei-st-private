# Metadata settings engine — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-meta-settings-rules.ps1` resolves every `F:`
token.

## Gate and router

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| GATE-1 | No stored gate | WHEN no gate value is stored, THE SYSTEM SHALL use the metadata engine | the fork's default build is v2 | `F:settings_store_router_test#defaults to the metadata engine` |
| GATE-2 | Legacy selected | WHEN the gate names v1, THE SYSTEM SHALL serve the legacy store | the rollback path must stay reachable | `F:settings_store_router_test#the gate selects the legacy engine` |
| GATE-3 | Hidden key | WHEN the key space is read, THE SYSTEM SHALL hide the gate key | the selector is not a setting and must not be exported | `F:settings_store_router_test#the gate key is hidden from the settings key space` |
| GATE-4 | Ignored write | WHEN a caller writes or removes the gate key through the store, THE SYSTEM SHALL ignore it | a stray write would change the next launch's engine | `F:settings_store_router_test#writes to the gate key are ignored by both engines` |
| GATE-5 | Clear | WHEN the settings are cleared, THE SYSTEM SHALL re-assert the gate | v1 shares the file that holds it | `F:settings_store_router_test#clear preserves the gate` |
| GATE-6 | Flush forwarding | WHEN the caller flushes settings, THE SYSTEM SHALL flush the active store | a pending v2 write must not survive the caller's await | `F:settings_store_router_test#flush is forwarded to the active store` |

## Initialization and switching

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| INIT-1 | Database unavailable | WHEN the metadata store cannot be opened, THE SYSTEM SHALL serve the session from v1 | an unopenable database must not take the app down | `F:settings_store_router_test#a metadata init failure falls back to the legacy engine for the session` |
| INIT-2 | Gate write fails | WHEN the gate cannot be persisted, THE SYSTEM SHALL abort the switch | the stored gate would override the in-memory choice | `F:settings_store_router_test#a failed gate write aborts the switch and leaves the engine unchanged` |
| INIT-3 | Failed switch state | WHEN a switch fails, THE SYSTEM SHALL keep the gate, the version and the active store on the old engine | a half-switched router points at an unreadable store | `F:settings_store_router_test#a failed switch keeps the gate, the version and the active store on the old engine` |
| INIT-4 | Diff replay | WHEN the switch commits, THE SYSTEM SHALL notify only the keys whose values differ | listeners cache brightness, refresh rate and layout | `F:settings_engine_controller_test#replaying a diff keeps the replayed keys out of the recent list` |
| INIT-5 | Recent list | WHEN a replay notifies a key, THE SYSTEM SHALL keep it out of the recent-change list | one switch would otherwise flood search suggestions | `F:settings_engine_controller_test#replaying a diff keeps the replayed keys out of the recent list` |
| INIT-6 | End-to-end switch | WHEN the controller switches engines, THE SYSTEM SHALL activate, replay, reset the locale cache and notify the surface | the steps span the router, `Settings` and the widget tree | `F:settings_engine_controller_test#switching to v2 activates the store and replays the differing key`; `F:settings_engine_controller_test#a switch whose store cannot open leaves the previous engine in place`; `F:settings_engine_controller_test#selecting the current engine does nothing` |
| INIT-7 | Default recent record | WHEN a key change is notified normally, THE SYSTEM SHALL treat it as a recent edit | the replay flag is the exception, not the rule | `F:settings_engine_controller_test#notifyKeyChange records a recent key by default` |

## Seeding

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SEED-1 | First switch seeds | WHEN v2 becomes authoritative for the first time, THE SYSTEM SHALL copy the legacy settings once | flipping the default must not reset an upgrading user | `F:settings_store_router_test#the first metadata init seeds the legacy settings once` |
| SEED-2 | Gate not copied | WHEN the seed runs, THE SYSTEM SHALL not copy the engine gate key | the selector is not a setting | `F:settings_store_router_test#seeding never copies the engine gate key into the metadata store` |
| SEED-3 | Stores stay independent | WHEN both engines have been used, THE SYSTEM SHALL keep their values independent | the rollback path must stay lossless | `F:settings_store_router_test#switching engines keeps the two stores independent after seeding` |
| SEED-4 | Resumable | WHEN a seed attempt fails, THE SYSTEM SHALL leave the marker unwritten and resume next time | a partial copy must not freeze the rest | `F:meta_settings_seeder_test#a partial seed aborts without the marker and resumes on the next attempt` |
| SEED-5 | No overwrite | WHEN a retry finds a key already copied, THE SYSTEM SHALL not overwrite it | the user may have changed it in v2 meanwhile | `F:meta_settings_seeder_test#an already copied key is never overwritten by a retry` |
| SEED-6 | One-shot marker | WHEN the marker exists, THE SYSTEM SHALL not seed again | a deliberate v2 reset must stay reset | `F:meta_settings_seeder_test#the marker makes seeding one-shot even if the legacy store changes` |
| SEED-7 | Internal state | WHEN a legacy key is internal, THE SYSTEM SHALL copy it only if it carries user-visible state | transient keys describe a session, not a preference | `F:meta_settings_seeder_test#an internal key carrying user-visible state migrates, transient ones do not` |
| SEED-8 | User-visible keys | WHEN a key belongs to a settings widget or the catalog, THE SYSTEM SHALL copy it | every rendered setting must survive the upgrade | `F:meta_settings_seeder_test#user-visible widget and catalog keys migrate` |

## Metadata store

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STORE-1 | Typed round trip | WHEN a typed value is written, THE SYSTEM SHALL read back the same value and type | sparse overrides must be type-stable | `F:meta_settings_store_test#typed values round trip through the database` |
| STORE-2 | Type mismatch | WHEN the stored type differs from the getter, THE SYSTEM SHALL return null | converting would invent a value | `F:meta_settings_store_test#a value of another type reads back as null` |
| STORE-3 | Key lifecycle | WHEN keys are read, removed or cleared, THE SYSTEM SHALL persist the change | export/reset read the key space | `F:meta_settings_store_test#getKeys, remove and clear are persisted` |
| STORE-4 | Failed write rollback | WHEN a write fails, THE SYSTEM SHALL roll the cache back to the persisted value | memory must not diverge from the database | `F:meta_settings_store_test#a failed write rolls the cache back instead of diverging` |
| STORE-5 | No clobber | WHEN a failed write is followed by a later write to the same key, THE SYSTEM SHALL keep the later value | re-syncing must not undo newer work | `F:meta_settings_store_test#a failed write does not clobber a later concurrent write to the same key` |
| STORE-6 | Re-sync | WHEN a write fails, THE SYSTEM SHALL re-sync the cache without re-emitting | listeners already saw the optimistic value | `F:meta_settings_store_test#a failed write re-syncs the cache to the persisted value` |
| STORE-7 | List runtime type | WHEN a list is written with a non-`List<String>` runtime type, THE SYSTEM SHALL persist it | a `List<dynamic>` of strings is still a string list | `F:meta_settings_store_test#put persists a list whose runtime type is not List<String>` |
| STORE-8 | Non-string list | WHEN a list holds a non-string element, THE SYSTEM SHALL skip it without retrying | the value cannot be represented | `F:meta_settings_store_test#put skips a list holding non-string elements without retrying` |
| STORE-9 | Flush waits | WHEN a caller awaits `flush`, THE SYSTEM SHALL wait for pending writes | batch callers rely on durability | `F:meta_settings_store_test#flush waits for pending writes and they are persisted` |
| STORE-10 | Flush idle | WHEN nothing is pending, THE SYSTEM SHALL resolve `flush` immediately | a no-op must stay cheap | `F:meta_settings_store_test#flush resolves immediately when nothing is pending` |
| STORE-11 | Flush failure | WHEN a pending write failed, THE SYSTEM SHALL not throw from `flush` | the error was already reported by the write | `F:meta_settings_store_test#flush does not throw when a pending write failed` |

## DAO and value codec

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| DAO-1 | Unreadable tag | WHEN a row carries an unreadable type tag, THE SYSTEM SHALL skip it and log | one bad row must not break the load | `F:settings_dao_test#a row with an unreadable type tag is skipped and logged` |
| DAO-2 | Enum tag | WHEN a row carries an enumeration tag, THE SYSTEM SHALL treat it as unreadable | the storage path persists enums by name | `F:settings_dao_test#an enumeration tag is unreadable, as the storage path never writes it` |
| DAO-3 | Upsert timestamp | WHEN a row is upserted, THE SYSTEM SHALL refresh `updatedAt` | the column answers "when did this change" | `F:settings_dao_test#upsert refreshes updatedAt on conflict` |
| CODE-1 | Type round trip | WHEN each supported type is encoded and decoded, THE SYSTEM SHALL return the same value | the type tag and the value must agree | `F:value_codec_test#bool round trips`; `F:value_codec_test#int round trips`; `F:value_codec_test#double round trips`; `F:value_codec_test#string round trips verbatim`; `F:value_codec_test#string list round trips through json` |
| CODE-2 | Malformed value | WHEN a stored value is malformed, THE SYSTEM SHALL decode it as null | a corrupt row must not throw on read | `F:value_codec_test#malformed values decode to null instead of throwing` |
| CODE-3 | Non-string array | WHEN a JSON array holds non-string elements, THE SYSTEM SHALL decode it as null | partial lists would silently drop values | `F:value_codec_test#a json array with non-string elements decodes to null` |

## Value guard

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| GRD-1 | Toggle | WHEN a toggle receives a non-boolean, THE SYSTEM SHALL reject it | the store has one type per key | `F:value_guard_test#accepts a bool for a toggle and rejects other types` |
| GRD-2 | Enum | WHEN an enum pick receives an unknown member, THE SYSTEM SHALL reject it | a stale member name must not reach the store | `F:value_guard_test#accepts a known enum member and rejects others` |
| GRD-3 | Custom | WHEN a custom def is written, THE SYSTEM SHALL pass the value through | the editor owns its own validation | `F:value_guard_test#passes custom values through untouched` |
| GRD-4 | Sub-page | WHEN a sub-page def is written, THE SYSTEM SHALL reject any value | a route is not a setting | `F:value_guard_test#rejects any value for a sub-page (it is a route, not a setting)` |

## Engine write path

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| ENG-1 | Toggle write | WHEN a toggle def is applied, THE SYSTEM SHALL write the value its reader then reports | the renderer has no typed setter of its own | `F:meta_settings_engine_test#a toggle def writes the value its reader reports` |
| ENG-2 | Rejected value | WHEN the guard rejects a value, THE SYSTEM SHALL leave the store unchanged | a bad edit must be a no-op | `F:meta_settings_engine_test#a rejected value never reaches the store` |
| ENG-3 | Enum by name | WHEN an enum def is applied, THE SYSTEM SHALL persist the member name | the store keeps primitive types only | `F:meta_settings_engine_test#an enum def persists the member name` |

## Catalog

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CAT-1 | Structure | WHEN the catalog is validated, THE SYSTEM SHALL accept the shipped defs | the release gate runs the same check | `F:catalog_test#passes its structural checks` |
| CAT-2 | Unique keys | WHEN two defs share a key, THE SYSTEM SHALL reject the catalog | a key routes one value | `F:catalog_test#keys are unique` |
| CAT-3 | Category header | WHEN a category has defs, THE SYSTEM SHALL give it a header | the surface groups by category | `F:catalog_test#every populated category has a header` |
| CAT-4 | Full coverage | WHEN a category exists, THE SYSTEM SHALL populate it | an empty category is an unfinished migration | `F:catalog_test#every category is populated` |
| CAT-5 | Category order | WHEN categories are rendered, THE SYSTEM SHALL place the wallpaper category before Advanced | the engine selector stays last | `F:catalog_test#Batch processing sits between Visible & wallpaper and Advanced` |
| CAT-6 | Sort order | WHEN defs are read, THE SYSTEM SHALL return them in sort order | the surface renders the list as-is | `F:catalog_test#defs are returned in sort order` |
| CAT-7 | Well-formed catalog | WHEN a catalog is well formed, THE SYSTEM SHALL report no problem | the validator must not cry wolf | `F:catalog_validation_test#accepts a well-formed catalog` |
| CAT-8 | Broken def | WHEN a def is duplicated or misses a per-kind field, THE SYSTEM SHALL report it | the compiler cannot check widget-kind completeness | `F:catalog_validation_test#flags duplicates and missing per-kind fields` |
| CAT-9 | Category migration | WHEN a category is declared migrated, THE SYSTEM SHALL cover its upstream settings | a half-ported category hides settings | `F:catalog_test#Display is fully migrated`; `F:catalog_test#Language is fully migrated`; `F:catalog_test#Accessibility is fully migrated`; `F:catalog_test#Privacy is fully migrated`; `F:catalog_test#Viewer is fully migrated`; `F:catalog_test#Video is fully migrated`; `F:catalog_test#Thumbnails is fully migrated`; `F:catalog_test#Navigation is fully migrated`; `F:catalog_test#Visible & wallpaper is fully migrated`; `F:catalog_test#Batch processing is fully migrated` |
| CAT-10 | Fork entries | WHEN the fork adds an entry, THE SYSTEM SHALL place it in its category | known issues sits under Advanced | `F:catalog_test#Known issues is reachable from Advanced`; `F:catalog_test#the Muzei wallpaper options left Advanced` |
| CAT-11 | Default-on toggle | WHEN a toggle has a default, THE SYSTEM SHALL render the default through its reader | a def must not duplicate `SettingsDefaults` | `F:catalog_test#the wallpaper prefetch option is a default-on toggle` |

## Surface, search and migration

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| RND-1 | Route names | WHEN pages are registered, THE SYSTEM SHALL mirror the upstream route names | a renamed route breaks deep links | `F:page_registry_test#page keys mirror the upstream route names` |
| RND-2 | Sub-page search keys | WHEN a sub-page def exists, THE SYSTEM SHALL give it a search-key entry | search must find the page's settings | `F:page_search_keys_test#every sub-page def has a search-key entry` |
| RND-3 | Search-key coverage | WHEN search keys are registered, THE SYSTEM SHALL cover exactly the sub-pages | a stale entry suggests a page that is gone | `F:page_search_keys_test#search keys cover exactly the registered sub-pages` |
| RND-4 | Route constants | WHEN search keys name pages, THE SYSTEM SHALL use the upstream constants | literals drift from the routes | `F:page_search_keys_test#search keys mirror the upstream page constants` |
| SRCH-1 | Plain def | WHEN a def has its own key, THE SYSTEM SHALL resolve the search to that key | a setting must be findable by the key it writes | `F:def_search_keys_test#a plain def resolves to its own key` |
| SRCH-2 | Sub-page resolution | WHEN a def opens a sub-page, THE SYSTEM SHALL resolve through the page's keys | the page writes keys the def does not name | `F:def_search_keys_test#a sub-page resolves through the page search keys` |
| SRCH-3 | Permissions page | WHEN the permissions entry is searched, THE SYSTEM SHALL resolve the keys its page writes | the entry itself owns no value | `F:def_search_keys_test#the permissions entry resolves to the keys its page writes` |
| SRCH-4 | Hidden filters | WHEN the video entry is searched, THE SYSTEM SHALL resolve the hidden-filter keys | the toggle edits those keys | `F:def_search_keys_test#the videoShowVideos entry resolves to the hidden-filter keys` |
| SRCH-5 | Search window | WHEN recent keys already match enough defs, THE SYSTEM SHALL stop growing the window | search must stay cheap | `F:def_search_test#stops at the target when the newest keys already match enough defs`; `F:def_search_test#grows the window until enough defs match` |
| SRCH-6 | Empty history | WHEN there is no history, THE SYSTEM SHALL return the target | search must work on a fresh install | `F:def_search_test#returns the target for an empty history` |
| SRCH-7 | Any key matches | WHEN one key of a def is recent, THE SYSTEM SHALL treat the def as matched | a def may write several keys | `F:def_search_test#treats a def as matched when any of its keys is recent` |
| MIGR-1 | Settings table | WHEN a v1 database upgrades, THE SYSTEM SHALL create the settings value table | the engine cannot store a value without it | `F:migration_v2_test#a v1 database upgrades to the current schema with the settings value table` |
