# Album contents transfer — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-album-contents-rules.ps1` resolves every `F:`
token.

## Scope and plans

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SCO-1 | Visible only | WHEN a scope is counted, THE SYSTEM SHALL count only rows inside the visible range | the action is defined over what the user sees | `F:album_contents_scope_test#counts only the rows inside the visible range` |
| SCO-2 | Live only | WHEN a scope is counted, THE SYSTEM SHALL ignore trashed rows | a trashed row is not a transfer candidate | `F:album_contents_scope_test#counts live entries only` |
| SCO-3 | Bounded feed | WHEN a scope is walked, THE SYSTEM SHALL read every row once in bounded batches | a long album must not be materialized | `F:album_contents_entry_feed_test#walks every row of the scope once, in bounded batches` |
| SCO-4 | Too large | WHEN a scope exceeds the shared limit, THE SYSTEM SHALL refuse to materialize it | a guess would act on the wrong set | `F:album_contents_entry_feed_test#refuses to materialize a scope past the shared limit` |
| PLA-1 | Destination inside source | WHEN the destination lies inside a source album, THE SYSTEM SHALL reject the plan | it would move a folder into itself | `F:album_contents_transfer_plan_test#rejects a destination inside one of the selected albums` |
| PLA-2 | Copy keeps sources | WHEN the plan is a copy, THE SYSTEM SHALL offer no folder cleanup | a copy does not empty the source | `F:album_contents_transfer_plan_test#plans a copy like a move, minus the folder cleanup` |

## Rename

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| REN-1 | Destination | WHEN the user submits a new name, THE SYSTEM SHALL place the album next to the original | a rename is not a move to another parent | `F:album_contents_rename_plan_test#places the renamed album next to the original` |
| REN-2 | Case-only | WHEN only the case changes, THE SYSTEM SHALL flag the rename for a two-step path | a case-insensitive file system treats both names as one | `F:album_contents_rename_plan_test#flags a rename that only changes the case` |
| REN-3 | Unsupported | WHEN the platform cannot rename the folder, THE SYSTEM SHALL fall back to the batched move | the folder may be on a provider that refuses it | `F:album_directory_rename_service_test#an unsupported folder falls back to the batched move` |
| REN-4 | Partial | WHEN the platform renamed some rows, THE SYSTEM SHALL report them before the batched path reads the old folder | a second move of an already-moved file fails | `F:album_directory_rename_service_test#a partial bulk move reports the rows that already moved` |
| REN-5 | Rows before state | WHEN the folder moved, THE SYSTEM SHALL rewrite the rows before moving the album state | a half-applied rename must not be read | `F:album_rename_outcome_applier_test#rewrites the rows, then moves the album state, then reloads the counts` |
| REN-6 | Failed rows | WHEN the row rewrite fails, THE SYSTEM SHALL not move the album state | cover, pins and bookmarks would point at a folder with no rows | `F:album_rename_outcome_applier_test#a failed row rewrite does not carry the album state over` |
| REN-7 | Narrowed view | WHEN the visible range leaves rows behind, THE SYSTEM SHALL refuse the folder rename | the folder and the view disagree | `F:album_rename_visibility_probe_test#a visible range that leaves rows behind blocks the rename` |
| REN-8 | Probe unavailable | WHEN the probe cannot read the database, THE SYSTEM SHALL keep the previous behaviour instead of refusing on a guess | the alternative blocks a real rename on a transient error | `F:album_rename_visibility_probe_test#a database behind the view never reports unseen rows` |
| REN-9 | Batched fallback | WHEN every item of the batched move fails, THE SYSTEM SHALL not move the album state | `doQuickMove` also reports success with failures | `-:widget flow, no host fixture` |
| REN-10 | Temporary name | WHEN a step of the two-step rename fails, THE SYSTEM SHALL leave the folder distinguishable | a rollback can fail too | `M` |

## Cleanup

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CLN-1 | Empty only | WHEN a source folder is cleaned up, THE SYSTEM SHALL remove only directories that are completely empty | a non-empty folder still holds user files | `F:empty_album_folder_cleaner_test#only removes directories that are completely empty` |
| CLN-2 | Unreadable | WHEN a directory is missing or unreadable, THE SYSTEM SHALL treat it as non-empty | a transient error must not delete anything | `F:empty_album_folder_cleaner_test#treats a missing or unreadable directory as non-empty` |
