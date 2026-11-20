# Batch processing — rule register

One row per case the feature has to get right. A behaviour that is not listed
here is a side effect nobody has named yet.

Columns:

- **Case** — the situation, in one line.
- **Evidence** — what the row has to show for the behaviour to be allowed.
- **Behaviour** — what the feature must do. Normative; `design.md` holds the
  invariants behind it.
- **Why** — the commit that made this a rule, then the sentence. No real path,
  title or account name.
- **Coverage** — `;`-separated tokens in one cell:
  - `F:<test file stem>#<test name>` — the test exists and fails when the rule
    breaks. `scripts/check-batch-rules.ps1` resolves every token.
  - `M` — needs a human on a device; the step is in `testing.md`.
  - `-:<reason>` — deliberately unfalsified.

A rule that stops being true is **superseded**, not deleted: keep the row, mark
it `superseded by <ID>` and leave the coverage that used to hold it.

## Run

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| RUN-1 | Output location | The job's output spec names the results folder | WHEN a run starts, THE SYSTEM SHALL write every output below `Pictures/aves_batch_results` | `0bd4476aa`: a run is non-destructive by construction | `F:batch_action_test#sends the default output folder` |
| RUN-2 | Selection filter | Only standard images reach the job | WHEN the selection holds videos or RAW files, THE SYSTEM SHALL drop them before building the job | `0bd4476aa`: batch uses the standard image decode path; RAW development is not ported | `F:batch_run_controller_test#runs only on standard images, skipping videos and RAW` |
| RUN-3 | Chain order | The job's tool list follows the sheet | WHEN several tools are enabled, THE SYSTEM SHALL send them in the sheet's order and SHALL drop disabled ones | `0bd4476aa`: tools describe pipeline work, so order is the user's | `F:batch_action_test#drops disabled actions from the native job` |
| RUN-4 | Cancellation | Finished results survive | WHEN a run is cancelled, THE SYSTEM SHALL keep every result already written and SHALL report the rest as failed or cancelled | `0bd4476aa`: cancellation is checked before each item, never mid-write | `M` |
| RUN-5 | Item failure | One bad item does not stop the job | WHEN an item fails, THE SYSTEM SHALL report it and SHALL continue with the next item | `0bd4476aa` | `M` |
| RUN-6 | Unknown tool | An older build ignores a newer tool | WHEN the job names a tool this build does not know, THE SYSTEM SHALL skip that tool and run the rest | `0bd4476aa`: a profile outlives a build | `-:native registry, no host fixture` |
| RUN-7 | Tool id contract | The spec carries the native id | WHEN a job is built, THE SYSTEM SHALL send each tool's native id rather than its Dart enum name | `0bd4476aa`: the id is the only contract with `BatchToolRegistry` | `F:batch_action_test#tool spec uses the native tool id` |
| RUN-8 | Footer default | Empty footer text means the file name | WHEN the footer has no text, THE SYSTEM SHALL draw the final file name | `0bd4476aa` | `F:batch_action_test#footer defaults to the automatic file name` |
| RUN-9 | Result metadata | A result keeps the source's capture metadata | WHEN a result is written, THE SYSTEM SHALL copy the source's capture time, camera and location onto it | `3c827fe54`: a re-encode has no EXIF of its own | `-:native bake runner, no host fixture` |

## Recording

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| REC-1 | Record on finish | One row per finished item | WHEN the native side reports `itemDone`, THE SYSTEM SHALL record the result | `3c827fe54`: the row is what makes a result actionable | `F:batch_run_controller_test#records only items the native side finished` |
| REC-2 | No row for unfinished items | A failed or cancelled item has no row | WHEN an item fails or a run is cancelled, THE SYSTEM SHALL NOT record that item | `3c827fe54`: a row for a missing file would offer actions on nothing | `F:batch_run_controller_test#records only items the native side finished` |
| REC-3 | Recorded facts | The row carries the assigned name, path, size and MIME | WHEN a result is recorded, THE SYSTEM SHALL store the facts the MediaStore assigned | `3c827fe54`: a guessed name diverges from the `(1)` suffix the store may add | `F:batch_results_service_test#records a result with its source and the actions that produced it` |
| REC-4 | Batch boundary | A run to another folder leaves the table empty | WHEN a run writes outside the results folder, THE SYSTEM SHALL NOT record its output | `3c827fe54`: the output path is the batch/share boundary | `F:batch_results_service_test#ignores a run that writes outside the results folder` |
| REC-5 | Action chain | The row keeps the chain that produced it | WHEN a result is recorded, THE SYSTEM SHALL store the action chain as profile JSON | `3c827fe54`: a result must be explainable after the sheet is gone | `F:batch_results_service_test#records a result with its source and the actions that produced it` |
| REC-6 | Record failure | The file exists even if the row does not | WHEN recording fails, THE SYSTEM SHALL log it and SHALL NOT fail the run | `3c827fe54`: a database error must not hide a finished file | `-:needs a failing recorder fixture` |
| REC-7 | Listing order | The page lists newest first | WHEN results are listed, THE SYSTEM SHALL order them newest first | `3c827fe54`: the most recent run is the one the user is looking for | `F:batch_result_store_test#lists results newest first` |
| REC-8 | Location follows the file | A rename rewrites the row | WHEN a result is renamed, THE SYSTEM SHALL rewrite its URI, path, name, MIME and size | `3c827fe54`: a rename gives the file a new MediaStore id | `F:batch_result_store_test#rewrites where a result lives` |
| REC-9 | Row deletion | Rows are removed by id | WHEN a result is applied or gone, THE SYSTEM SHALL delete its row | `3c827fe54`: a tombstone would still render and still count | `F:batch_result_store_test#deletes rows by id` |

## Repeat runs

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| REP-1 | Replace previous | One pending result, plain name | WHEN a source is processed again in replace-previous mode, THE SYSTEM SHALL park the older file as `<name>-to-remove`, give the new one the plain name, then delete the parked file | `3c827fe54`: writing before parking makes the MediaStore add `(1)` | `F:batch_results_service_test#replace-previous parks and deletes the older result, then frees its name` |
| REP-2 | Supersede failure | No file is lost | WHEN parking or deleting the older result fails, THE SYSTEM SHALL leave both files in place | `3c827fe54`: a half-finished cleanup must not delete the only copy | `-:needs a failing native fixture` |
| REP-3 | Keep versions | Every version stays pending | WHEN keep-versions is selected, THE SYSTEM SHALL name results `{name}_{date}` and SHALL keep every version pending | `3c827fe54` | `F:batch_results_service_test#keep-versions leaves both results pending` |
| REP-4 | Supersede scope | Applied results are never touched | WHEN a source has an older result, THE SYSTEM SHALL supersede only the pending ones | `3c827fe54`: an applied result no longer has a row | `F:batch_result_store_test#finds older pending results of one source` |

## Applying

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| APP-1 | Replace | Source bytes change, result file is consumed | WHEN the user confirms replace, THE SYSTEM SHALL overwrite the source bytes in place and SHALL delete the result file | `3c827fe54` | `F:batch_results_service_test#replacing a source consumes its result and keeps the row count honest` |
| APP-2 | Replace failure | The row stays pending | WHEN a replacement fails, THE SYSTEM SHALL keep the row pending | `3c827fe54`: the user can retry or move it back | `F:batch_results_service_test#a failed replacement keeps the result pending` |
| APP-3 | Format change | The source row takes the result's name and MIME | WHEN the result uses another format, THE SYSTEM SHALL update the source row's name and MIME type and SHALL keep its date columns | `3c827fe54`; `239ea4a40`: a row update is cheaper and safer than a rescan | `-:native BatchResultFiles, no host fixture` |
| APP-4 | Write access | One request before the first write | WHEN a replacement needs scoped-storage access, THE SYSTEM SHALL request it once for the whole selection before writing | `3c827fe54`; `2afb33613`: lazy escalation, one prompt per batch | `F:batch_results_service_test#replacing a source consumes its result and keeps the row count honest` |
| APP-5 | Move back | Files land in the source folder | WHEN the user confirms move back, THE SYSTEM SHALL move each result into its source directory and SHALL rename on a name conflict | `3c827fe54`; `e6c76c8f1`: a transfer must never overwrite a same-named file | `F:batch_results_service_test#moving back uses the source folder and renames on conflict` |
| APP-6 | No move into the results tree | A result whose source is the results folder cannot move back | WHEN a result's source directory is inside the results tree, THE SYSTEM SHALL NOT offer move back | `3c827fe54`: moving a copy into the folder it already lives in only renames it | `-:model predicate, no fixture` |

## Housekeeping

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| HOU-1 | Vanished result | The row disappears with the file | WHEN the results page or banner opens, THE SYSTEM SHALL drop rows whose result file no longer exists | `25a3f5a19`: a deleted file leaves nothing for the change cursor, so the row outlives it | `F:batch_results_service_test#prunes rows whose result file disappeared` |
| HOU-2 | Parked leftovers | No `-to-remove` file survives a later run | WHEN a run finishes, THE SYSTEM SHALL delete the parked files it knows about | `3c827fe54`: an interrupted cleanup leaves a visible file | `-:needs a storage fixture` |
| HOU-3 | Fresh result | A just-written result is not pruned | WHEN a result is not in the app's table yet, THE SYSTEM SHALL ask the platform before dropping it | `3c827fe54`: the scanner lags behind the write | `-:needs a platform fixture` |

## Classification

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| CLS-1 | Path recognition | The results root is recognised on any volume and case | WHEN a directory path names the results folder, THE SYSTEM SHALL recognise it as the results tree | `3c827fe54` | `F:batch_paths_test#recognizes the results folder on any volume and case` |
| CLS-2 | Subfolders | A subfolder belongs to the tree | WHEN a directory lies below the results root, THE SYSTEM SHALL treat it as part of the tree | `3c827fe54` | `F:batch_paths_test#recognizes a subfolder of the results tree` |
| CLS-3 | Sibling prefix | `..._old` is not the results folder | WHEN a path only shares the root's prefix, THE SYSTEM SHALL NOT treat it as the tree | `3c827fe54`: a prefix match would capture an unrelated album | `F:batch_paths_test#does not match a sibling folder with the same prefix` |
| CLS-4 | Relative spec | The batch/share boundary is exact | WHEN the output spec is exactly the results folder, THE SYSTEM SHALL accept the run as a batch run | `3c827fe54` | `F:batch_paths_test#recognizes the relative output spec exactly` |
| CLS-5 | Banner scope | No banner outside the results album | WHEN the visible filters are not exactly the results album, THE SYSTEM SHALL NOT show the banner | `3c827fe54`: the banner offers to overwrite originals | `-:widget, no fixture` |
| CLS-6 | One-time pin | Unpinning sticks | WHEN the results folder was pinned once, THE SYSTEM SHALL NOT pin it again | `3c827fe54`: a user who unpins must not be overruled | `-:needs a settings fixture` |
| CLS-7 | App classification | The folder groups under Apps | WHEN the results folder is listed, THE SYSTEM SHALL classify it as an app album | `3c827fe54`; `bc6f41611`: the staging tree set the precedent | `-:one-line branch in android_file_utils, no fixture` |

## Profiles

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| PRF-1 | Seed | One default profile per kind | WHEN the run sheet or settings page opens, THE SYSTEM SHALL ensure one default profile per kind | `3c827fe54`: the sheet must have a starting point | `F:batch_result_store_test#seeds one active default per kind` |
| PRF-2 | Kinds | Batch and share do not mix | WHEN profiles are listed, THE SYSTEM SHALL return only the requested kind | `3c827fe54`: copy & share will reuse the table | `F:batch_result_store_test#keeps kinds apart` |
| PRF-3 | Active | Activation is exclusive | WHEN a profile is activated, THE SYSTEM SHALL deactivate the others of its kind | `3c827fe54` | `F:batch_result_store_test#activating one profile deactivates the others` |
| PRF-4 | Delete | Only the row is removed | WHEN a profile is deleted, THE SYSTEM SHALL remove only its row | `3c827fe54`: photos are not configuration | `F:batch_result_store_test#deletes a profile without touching the files` |
| PRF-5 | Join on kind | Unknown rows are ignored | WHEN a profile holds an action this build cannot show, THE SYSTEM SHALL ignore that action and apply the rest | `3c827fe54`: the sheet owns one row per runnable tool | `-:widget, no fixture` |
| PRF-6 | Round-trip | Kind, settings and the disabled flag survive | WHEN a chain is saved and reloaded, THE SYSTEM SHALL keep its kind, settings and disabled flag | `3c827fe54`: a profile is configuration, not a run | `F:batch_action_test#round-trips a filter action through JSON`; `F:batch_action_test#keeps the disabled flag through JSON` |
| PRF-7 | Unknown action | A newer profile still opens | WHEN a stored action names a kind this build does not know, THE SYSTEM SHALL drop that action and keep the rest | `3c827fe54`: a profile outlives a build | `F:batch_action_test#ignores an unknown action kind` |

## Schema

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| SCH-1 | Upgrade | A v16 database gains the tables | WHEN a v16 database opens, THE SYSTEM SHALL create the batch tables and indexes | `3c827fe54`: the feature needs durable bookkeeping | `F:migration_v17_test#a v16 database upgrades to v17 with the batch tables and indexes` |
| SCH-2 | Fresh install | A fresh v17 database matches | WHEN a fresh database is created, THE SYSTEM SHALL create the same tables and indexes | `3c827fe54`: a fresh install must not differ from an upgrade | `F:migration_v17_test#a fresh v17 database has the same tables and indexes` |

## Results UI

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| UI-1 | No delete | The menu has no delete entry | THE SYSTEM SHALL NOT offer a delete action in the batch results UI | `3c827fe54`: album multi-select already deletes | `-:widget, no fixture` |
| UI-2 | Not now | The banner hides, the rows stay | WHEN the user chooses "not now", THE SYSTEM SHALL hide the banner for that view and SHALL keep every row pending | `3c827fe54`: hiding is not a decision | `-:widget, no fixture` |
| UI-3 | Range gesture | A long press flips the interval | WHEN the user long-presses a result after tapping another, THE SYSTEM SHALL apply the shared XOR-range rule | `3c827fe54`; the gesture itself is owned by `features/selection_xor` | `-:shared selection_xor suite` |

## Copy & share

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| SHR-1 | Share root | The share folder is recognised on any volume and case | WHEN a directory path names the share folder, THE SYSTEM SHALL recognise it as the share tree | copy & share: the folder is app-owned and temporary | `F:batch_paths_test#recognizes the share folder on any volume and case` |
| SHR-2 | Share subfolders | A subfolder belongs to the share tree | WHEN a directory lies below the share root, THE SYSTEM SHALL treat it as part of the tree | copy & share: the tree, not one exact folder | `F:batch_paths_test#recognizes a subfolder of the share tree` |
| SHR-3 | Share sibling prefix | `..._old` is not the share folder | WHEN a path only shares the root's prefix, THE SYSTEM SHALL NOT treat it as the tree | copy & share: a prefix match would capture an unrelated album | `F:batch_paths_test#does not match a sibling folder with the same prefix` |
| SHR-4 | Share is not batch | The two roots stay disjoint | WHEN a path is inside the share tree, THE SYSTEM SHALL NOT treat it as the results tree, and the reverse | copy & share: the recorder gate depends on the two roots never overlapping | `F:batch_paths_test#does not treat the share folder as batch results` |
| SHR-5 | Share relative spec | The share output spec is exact | WHEN an output spec is exactly the share folder, THE SYSTEM SHALL treat it as share output and SHALL NOT record it as a batch result | copy & share: the relative path is the boundary before an absolute path exists | `F:batch_paths_test#recognizes the share relative output spec exactly` |
| SHR-6 | No batch row | A share run leaves the batch table empty | WHEN a share run finishes an item, THE SYSTEM SHALL NOT insert a batch result row | copy & share: share output has no replace or move-back decision | `F:batch_results_service_test#ignores a copy & share run` |
| SHR-7 | App classification | The share folder groups under Apps | WHEN the share folder is listed, THE SYSTEM SHALL classify it as an app album | copy & share: it is temporary output, not a user album | `F:android_file_utils_test#app album classification` |
| SHR-8 | Share run wiring | Share output uses the share root and a dated name | WHEN a share run is built, THE SYSTEM SHALL write to the share root and name each copy `{name}_{date}` | copy & share: there is no supersede pass, so a plain name would collide | `-:run wiring, no host fixture` |
| SHR-9 | Retention removes old copies | Only files older than the cutoff are removed | WHEN a share copy is older than the configured retention, THE SYSTEM SHALL delete it permanently and remove its row | copy & share: the folder is temporary | `F:batch_share_service_test#removes only files older than the cutoff` |
| SHR-10 | Retention boundary | A file exactly at the cutoff survives | WHEN a share copy is exactly at the cutoff, THE SYSTEM SHALL keep it | copy & share: the boundary must be explicit, not incidental | `F:batch_share_service_test#keeps a file exactly at the cutoff` |
| SHR-11 | Unknown age | An unreadable modified time is not old age | WHEN a share copy's modified time is unknown, THE SYSTEM SHALL keep it | copy & share: deleting a fresh copy is worse than keeping an old one | `F:batch_share_service_test#keeps a file whose modified time is unknown` |
| SHR-12 | Retention scope | Batch results and sources are never candidates | WHEN retention runs, THE SYSTEM SHALL read only the share folder and SHALL NOT delete a batch result or a source | copy & share: the results lifecycle is separate | `F:batch_share_service_test#never removes a batch result or a source` |
| SHR-13 | Retention off | Off deletes nothing | WHEN retention is off, THE SYSTEM SHALL NOT read or delete any share copy | copy & share: "keep until I delete" is a real choice | `F:batch_share_service_test#does nothing when retention is off` |
| SHR-14 | Failed delete | A failed delete keeps the row | WHEN deleting a share copy fails, THE SYSTEM SHALL keep its row and report nothing removed | copy & share: the row is the only way to find the file again | `F:batch_share_service_test#a failed delete keeps the row and reports nothing removed` |
| SHR-15 | Retention setting | Only an offered value is honoured | WHEN the stored retention is not one of the offered values, THE SYSTEM SHALL fall back to the default | copy & share: a hand-edited row must not disable cleanup silently | `F:batch_settings_test#parses only an offered retention value` |
| SHR-16 | Retention round-trip | The choice survives a reload | WHEN the retention is changed, THE SYSTEM SHALL persist it and read it back | copy & share: the setting outlives the page | `F:batch_settings_test#round-trips the retention choice` |
| SHR-17 | Share profiles | Only share profiles are offered | WHEN the share sheet or share settings page opens, THE SYSTEM SHALL seed and list only `share` profiles | copy & share: profiles are joined by kind | `F:batch_result_store_test#seeds one active default per kind`; `F:batch_result_store_test#keeps kinds apart` |
| SHR-18 | Explainer marker | The explainer is shown once per install | WHEN the explainer has been shown, THE SYSTEM SHALL NOT show it again after a preference reset | copy & share: the marker lives in `appMeta`, like the results pin | `F:batch_settings_test#remembers the share explainer once shown` |
| SHR-19 | No automatic share sheet | The run ends at the album | WHEN a share run finishes, THE SYSTEM SHALL offer to open the share album and SHALL NOT open a system share sheet | copy & share: the user may review or pick a subset first | `-:widget, no fixture` |
| SHR-20 | Explainer and settings entry | The first run explains the folder and offers settings | WHEN the user starts copy & share for the first time, THE SYSTEM SHALL show the explainer with a settings entry before the sheet | copy & share: the folder is temporary and not a backup | `M` |
