# Drift database — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-drift-db-rules.ps1` resolves every `F:` token.

## Connection and schema

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| DB-1 | One connection | WHEN two callers open the database, THE SYSTEM SHALL return the same connection | the settings store and the media DB must not fight over two handles | `F:app_database_provider_test#open returns the same connection to later callers` |
| DB-2 | Retry open | WHEN an open attempt fails, THE SYSTEM SHALL drop it so a later call retries | a transient busy disk must not poison the process | `F:app_database_provider_test#open retries after a transient failure instead of staying poisoned` |
| DB-3 | Close | WHEN the provider is closed, THE SYSTEM SHALL drop the cached connection | a later test or session must reopen cleanly | `F:app_database_provider_test#close drops the cached connection so a later open reopens` |
| DB-4 | Column names | WHEN the schema is generated, THE SYSTEM SHALL keep the upstream camelCase column names | queries and the legacy import depend on them | `F:drift_local_media_db_test#schema pins legacy camelCase column names` |
| DB-5 | Entry round trip | WHEN an entry is written, updated and removed, THE SYSTEM SHALL read back the same row | the whole app reads this table | `F:drift_local_media_db_test#entries round trip, update and remove` |
| DB-6 | Identity | WHEN the media store reports the same file twice, THE SYSTEM SHALL keep one row | a duplicate doubles the library | `F:drift_local_media_db_test#a repeated media-store report does not take a second row` |
| DB-7 | Domains | WHEN a domain table is written and read, THE SYSTEM SHALL round-trip its value | each feature owns one table | `F:drift_local_media_db_test#catalog metadata and date taken`; `F:drift_local_media_db_test#addresses`; `F:drift_local_media_db_test#favourites`; `F:drift_local_media_db_test#covers`; `F:drift_local_media_db_test#dynamic albums`; `F:drift_local_media_db_test#video playback`; `F:drift_local_media_db_test#vaults`; `F:drift_local_media_db_test#trash`; `F:drift_local_media_db_test#debug log` |
| DB-8 | Store logging | WHEN the store writes, THE SYSTEM SHALL log through the feature channel and write nothing when it is closed | a closed channel must not grow the file | `F:drift_store_logging_test#an open log.db channel receives store records at debug level`; `F:drift_store_logging_test#a closed log.db channel receives nothing` |

## Queries

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| QRY-1 | Windows | WHEN a window is read, THE SYSTEM SHALL count, order and clamp it exactly like the in-memory path | the two engines must agree | `F:entry_window_test#counts all non-trashed entries by default`; `F:entry_window_test#counts a single directory level only`; `F:entry_window_test#walks the whole collection without loss or duplication`; `F:entry_window_test#orders by bestDate descending, then reverses whole-list`; `F:entry_window_test#clamps degenerate windows`; `F:entry_window_test#supports trashed-only windows with restore details` |
| QRY-2 | Filters | WHEN a filter is compiled, THE SYSTEM SHALL match the in-memory filter for every supported kind | a mismatch shows the wrong rows | `F:entry_window_test#filters intersect (AND)`; `F:entry_window_test#hidden filters are excluded from the window`; `F:entry_window_test#an album group selects its members`; `F:entry_window_test#tags select tagged entries; the empty tag selects untagged`; `F:entry_window_test#a dynamic album unwraps to its inner filter`; `F:entry_window_test#mime and rating filters read metadata`; `F:entry_window_test#a location filter reads the address`; `F:entry_window_test#a path filter matches the root and its descendants only` |
| QRY-3 | Reversed filters | WHEN a filter is reversed, THE SYSTEM SHALL keep the rows without the field | a NULL-unsafe negation drops them | `F:entry_window_test#a reversed album keeps entries without a directory`; `F:entry_window_test#a reversed tag keeps untagged entries`; `F:entry_window_test#a reversed mime keeps other mime types`; `F:entry_window_test#a reversed rating keeps unrated entries`; `F:entry_window_test#a reversed location keeps entries without an address`; `F:entry_window_test#a reversed filter used as a hidden filter hides its complement` |
| QRY-4 | Unsupported filters | WHEN a filter cannot be expressed in SQL, THE SYSTEM SHALL report it so the caller keeps the legacy path | a wrong predicate is worse than a fallback | `F:entry_window_test#a regular-expression query keeps the legacy path`; `F:entry_window_test#non-gregorian calendars keep the legacy path`; `F:entry_window_test#a non-Gregorian field query keeps the legacy path` |
| QRY-5 | Sections | WHEN sections are read, THE SYSTEM SHALL group albums, months, days and ratings like the in-memory layout | the header counts must match the grid | `F:entry_section_test#groups albums with counts in path order`; `F:entry_section_test#groups Gregorian months and days`; `F:entry_section_test#groups ratings with unrated defaulting to zero`; `F:entry_section_test#single returns the window total as one header` |
| QRY-6 | Stacks | WHEN a stack is settled, THE SYSTEM SHALL keep one tile and re-home the frames when it leaves | a stack must hide nothing else | `F:entry_stack_test#inserting a burst frame settles the group tile`; `F:entry_stack_test#a developed image hides its raw sibling`; `F:entry_stack_test#deleting the tile re-homes the group`; `F:entry_stack_test#deleting a frame keeps the tile` |
| QRY-7 | Summaries | WHEN summaries are read, THE SYSTEM SHALL exclude trash, hidden albums and locked vaults | a count must describe what the grid shows | `F:filter_summary_test#groups by directory with count, size and best date`; `F:filter_summary_test#excludes trashed entries`; `F:filter_summary_test#excludes hidden albums and locked vaults`; `F:filter_summary_test#splits multi-tag subjects and aggregates per tag`; `F:filter_summary_test#groups countries, states and places` |
| QRY-8 | Directory rename | WHEN a directory is renamed, THE SYSTEM SHALL move its rows, keep their identity and leave siblings | the file moved, the rows must follow | `F:entry_directory_rename_test#moves the folder rows, keeps their identity, and leaves siblings alone`; `F:entry_directory_rename_test#moves a burst group together, keeping its key shape and its tile`; `F:entry_directory_rename_test#countInDirectory counts what the folder holds, not what a view shows` |
| QRY-9 | Catalogue backlog | WHEN the backlog is queried, THE SYSTEM SHALL use keyset pagination and honour a scope | a backlog over a huge library must not materialize | `F:catalog_coverage_test#lists entries missing metadata with keyset pagination`; `F:catalog_coverage_test#sweeps album by album, with a cursor inside an album`; `F:catalog_coverage_test#limits the catalog backlog to a scope`; `F:catalog_coverage_test#lists gps entries missing addresses with keyset pagination` |

## Migrations

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| MIG-1 | Settings table | WHEN a v1 database upgrades, THE SYSTEM SHALL create the settings value table | the v2 settings engine cannot store a value without it | `F:migration_v2_test#a v1 database upgrades to the current schema with the settings value table` |
| MIG-2 | Directory | WHEN a v2 database upgrades, THE SYSTEM SHALL backfill and index `entry.directory` | every window and summary query reads it | `F:migration_v3_test#a v2 database upgrades to v3 with directories backfilled and indexed` |
| MIG-3 | Stack index | WHEN a v3 database upgrades, THE SYSTEM SHALL fill the stack index | a missing tile shows duplicate frames | `F:migration_v4_test#a v3 database upgrades to v4 with the stack index filled` |
| MIG-4 | Range tables | WHEN a v4 database upgrades, THE SYSTEM SHALL create the visible-range tables | the feature cannot store a range without them | `F:migration_v5_test#a v4 database upgrades with the visible-range tables` |
| MIG-5 | Descriptions | WHEN a v5 database upgrades, THE SYSTEM SHALL add empty descriptions | the column is part of the rule model | `F:migration_v6_test#a v5 database upgrades to v6 with empty descriptions` |
| MIG-6 | Groups | WHEN a v6 database upgrades, THE SYSTEM SHALL create the wallpaper-group table and its index | groups are the feature's root row | `F:migration_v7_test#a v6 database gains the wallpaper-group table and its index` |
| MIG-7 | Usage | WHEN a v7 database upgrades, THE SYSTEM SHALL add the group description and the usage table and drop sessions | applied-target bookkeeping replaced session history | `F:migration_v8_test#a v7 database gains the usage table and a described group` |
| MIG-8 | Base active | WHEN a v8 database upgrades, THE SYSTEM SHALL add the base activation flag as active | an existing range must keep restricting | `F:migration_v9_test#a v8 database gains the base activation flag as active` |
| MIG-9 | Effects | WHEN a v9 database upgrades, THE SYSTEM SHALL add effects as the identity | an upgraded group keeps its untouched photos | `F:migration_v10_test#a v9 database gains the effects column as the identity` |
| MIG-10 | Interval | WHEN a v10 database upgrades, THE SYSTEM SHALL add interval and ordering and adopt the global ordering | the user's chosen order must survive the move | `F:migration_v11_test#a v10 database adopts the global ordering and gains the interval` |
| MIG-11 | History | WHEN a v11 database upgrades, THE SYSTEM SHALL create the grouped wallpaper history table | the page labels what was shown | `F:migration_v12_test#a v11 database gains the history table and its index` |
| MIG-12 | Surface | WHEN a v12 database upgrades, THE SYSTEM SHALL rebuild the history with a surface and add the lock-range flag | SQLite cannot alter the unique key in place | `F:migration_v13_test#a v12 history row moves to the home surface` |
| MIG-13 | Pool | WHEN a v13 database upgrades, THE SYSTEM SHALL fold the lock range into the group's condition pool | one condition set per group | `F:migration_v14_test#a v13 lock range merges into the home pool` |
| MIG-14 | Edit sessions | WHEN a v14 database upgrades, THE SYSTEM SHALL create the edit session and output tables | the copy-first feature needs both | `F:migration_v15_test#a v14 database gains the edit session and output tables` |
| MIG-15 | Merge duplicates | WHEN a v15 database upgrades, THE SYSTEM SHALL merge duplicate media-store rows | two rows for one file double the library | `F:migration_v16_test#a v15 database upgrades to v16 with the duplicate rows merged` |
| MIG-16 | Batch tables | WHEN a v16 database upgrades, THE SYSTEM SHALL create the batch tables and indexes | results and profiles need their tables | `F:migration_v17_test#a v16 database upgrades to v17 with the batch tables and indexes` |
| MIG-17 | Collection-aware identity | WHEN a v17 database upgrades, THE SYSTEM SHALL make the media-store identity collection-aware | the same number can name an image and a video | `F:migration_v18_test#a v17 database upgrades to v18 with a collection-aware identity` |

## Legacy import

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| LEG-1 | Full import | WHEN a legacy database exists, THE SYSTEM SHALL import every table, keep a backup and be idempotent | a failed run must not duplicate the library | `F:legacy_import_test#imports every legacy table, keeps a backup, and is idempotent` |
| LEG-2 | No legacy file | WHEN there is no legacy file, THE SYSTEM SHALL mark the import done without creating one | a fresh install has nothing to import | `F:legacy_import_test#fresh install without a legacy file just marks the import done` |
| LEG-3 | Resume | WHEN an import is interrupted, THE SYSTEM SHALL resume from the last committed chunk | a long import must survive a kill | `F:legacy_import_test#resumes from the last committed chunk after an interruption` |
| LEG-4 | One actor | WHEN another actor owns the import, THE SYSTEM SHALL wait instead of starting a second | two imports would interleave chunks | `F:legacy_import_test#a second actor waits while another owns the import` |
| LEG-5 | Verify | WHEN verification finds a mismatch, THE SYSTEM SHALL reconcile from a clean slate | a half-imported table is worse than a restart | `F:legacy_import_test#reconciles a verification mismatch from a clean slate` |
| LEG-6 | Progress | WHEN progress is reported, THE SYSTEM SHALL keep it monotonic and reach the total | the status must not jump back | `F:legacy_import_test#progress is monotonic and reaches the total` |
| LEG-7 | Corrupt cursor | WHEN the persisted cursor is corrupt, THE SYSTEM SHALL restart the import | a bad marker must not brick the upgrade | `F:legacy_import_test#a corrupt persisted cursor restarts instead of bricking the import` |
| LEG-8 | Chunking | WHEN a text-keyed table is imported, THE SYSTEM SHALL chunk it instead of loading it whole | a large table would exhaust memory | `F:legacy_import_test#chunks the text-keyed tables instead of loading them whole` |

## Generated code

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| GEN-1 | Regeneration | WHEN a table, column or migration changes, THE SYSTEM SHALL regenerate and commit `app_database.g.dart` | a stale schema fails at runtime, not at compile time | `-:governance, enforced by review and a clean analyze` |
