# Batch processing — design

How the feature works, and the invariants a change must preserve. The behaviour
itself is specified in `spec.md`; the testable cases are in `rules.md`.

## 1. Shape of the slice

```
lib/features/batch_ops/
  model/     batch_action, batch_job, batch_paths, batch_result
  db/        batch_result_store, batch_profile_store, batch_result_tables
  services/  batch_service (channel), batch_run_controller, batch_results_service,
             batch_result_recorder, batch_settings
  view/      run sheet, action editor, progress dialog, results page,
             results banner, settings page, tool catalog
```

The Dart side owns selection, configuration, progress and every database write.
The native side owns decoding, adjustment replay, encoding and the MediaStore
writes. Neither side guesses what the other knows: the job carries the source
facts, and `itemDone` carries the facts of the file that was just written.

## 2. Pipeline

```
collection/viewer action
  -> startBatch()                      filters images, loads settings
  -> BatchRunSheet                     ordered, enabled tool chain
  -> BatchRunController.run()          builds BatchJob, subscribes to the stream
  -> batch_stream channel              arguments are the whole job
  -> BatchStreamHandler                parses, launches on the IO scope
  -> BatchExecutor                     one item at a time, cancellation between items
  -> BatchToolRegistry                 tools describe work, they never touch pixels
  -> BatchPipeline                     accumulated adjustments/resize/footer/format
  -> RefraBakeRunner                   one decode, full replay, optional composite, one encode
  -> MediaStore insert                 relative path + name pattern + format
  -> copyExifToUri                     source capture metadata onto the result
  -> itemDone event                    uri, path, name, size, mimeType
  -> BatchResultsService.record()      gate on the output path, insert the row
```

Why one decode and one encode: a chain of six tools would otherwise re-encode six
times, losing quality each round and making the run time depend on the chain
length. Tools therefore only fill `BatchPipeline`; the runner performs the work
once.

### Item isolation

`BatchExecutor` checks cancellation before each item and never in the middle of
a write. An exception is caught per item and reported as `itemFailed`. This is
what makes "partial completion" true rather than aspirational.

## 3. Data model

Two tables, schema 17 (see `contracts/batch-results-schema.md`):

- `batch_results` — one row per result file, keyed by `${jobId}-${index}`.
- `batch_profiles` — saved action chains, keyed by id, separated by `kind`
  (`batch` or `share`).

**The table is the source of truth, not the folder.** The folder cannot say
which source a copy came from, so "replace the original" and "move it back"
would be guesses. A file dropped into the folder by another app has no row and
is therefore never touched.

`BatchResult` exposes the two predicates every action uses:

- `canReplaceSource` — the row knows a source URI.
- `canMoveBack` — the row knows a source directory, and that directory is not
  inside the results tree.

## 4. Result lifecycle

```
record()
   |
   v
[pending] -- replace succeeds ----> (row deleted)
   |
   +------- move succeeds --------> (row deleted)
   |
   +------- file no longer exists -> (row deleted)
```

`status` is stored as `pending`. The `applied` and `discarded` values exist in
the model and are rendered by the results page, but v1 does not write them: an
applied result loses its row instead of keeping a tombstone. See §11.

## 5. Naming and the supersede sequence

`batchResultsRelativeRoot` is `Pictures/aves_batch_results`; `BatchOutput`
defaults to it. The name pattern comes from the result mode:

- replace previous: `{name}`;
- keep versions: `{name}_{date}`.

In replace-previous mode a new result may collide with the older one, and a
MediaStore insert on a taken name becomes `name (1).jpg`. The sequence avoids
that:

1. insert and record the new result;
2. rename the older pending file to `<base>-to-remove.<ext>`;
3. delete the parked file;
4. rename the new result to `<base>.<ext>`;
5. rewrite the new row's URI, path, name, MIME and size.

A failure at any step leaves both files on disk: the new result keeps its
`(1)` name and the old one keeps its parked name. `pruneSupersededFiles()` then
removes parked files a later run finds in the app's table.

`isBatchResultsPath` and `isBatchResultsRelativePath` normalise separators and
case. The relative variant is exact (the folder itself), because it decides
whether an item belongs to the batch table before an absolute path exists.

## 6. Applying a result

### Replace the original

`BatchResultsService.replaceWithSource`:

1. request write access once for the whole selection (chunks of 2000 URIs, the
   `MediaStore.createWriteRequest` limit);
2. per result, call native `replaceWithResult`;
3. on success, refresh the source row from the platform and delete the result
   row;
4. on failure, leave the row pending.

Native `BatchResultFiles.replace` writes through `overrideImageStreaming`, which
keeps the source row's date columns and restores the original bytes if the write
fails. When the result's display name differs, the source row takes the result's
name and MIME type, so a PNG never keeps a `.jpg` label. The result file is then
deleted permanently — a consumed result in the recycle bin would be noise.

### Move back

`moveBack` groups the result entries by their recorded source directory, runs one
`MediaEditService.move` with `copy: false` and `NameConflictStrategy.rename`,
then:

- syncs the app's rows through `_syncAfterTransfer` (the MediaStore already
  changed; the app's rows must follow);
- deletes the rows of the files that moved.

Rename-on-conflict is the point: move back is the non-destructive alternative to
replace, so it must never overwrite a same-named file.

### Row synchronisation

`_syncAfterTransfer` handles both a rename and a move. When the volume keeps the
id, the row is updated in place; otherwise the new file is inserted with a fresh
row id and the old row is removed. This is why a row's `resultUri` is never
treated as identity after a file operation.

## 7. Permissions

Scoped storage refuses a write to a file the app does not own. The batch feature
asks once, before the first write, for the whole selection — not per photo. A
denial is not fatal: files the app owns still write, and the per-item outcome
reports the rest. The same lazy-escalation idea already exists in
`features/media_ops` (`MediaOpPermissions`), which is why the batch handler
reuses it instead of inventing a second prompt policy.

## 8. UI surfaces

| Surface | Reads | Writes |
| --- | --- | --- |
| Run sheet | runnable catalog, profiles | a profile on save |
| Progress dialog | controller counts and state | cancel |
| Results album banner | pending rows | replace / move back |
| Results page | all rows, app entries for thumbnails | replace / move back, selection |
| Settings › Batch | settings, profiles, pending count | result mode, active profile, delete profile |

The banner appears only when the visible filters are exactly the results album
(`_isBatchResultsView`). A broader album that merely contains the folder, or a
multi-filter view, gets no banner: the banner offers to overwrite originals, so
it must only appear where the user is looking at results.

The results page and the banner both call `pruneMissingResults()` before
reading, so a result deleted from the album cannot keep offering an action.

## 9. Invariants

- **I1** A run writes only below the results folder.
- **I2** A file without a result row is never replaced, moved or deleted by this
  feature.
- **I3** A row is deleted only after its file operation succeeded, or after the
  platform confirmed the file is gone.
- **I4** A result is not a backup. Replacing an original is destructive and has
  no undo.
- **I5** Replace-previous leaves one pending result per source; keep-versions
  leaves many.
- **I6** The output relative path is the boundary between batch results and
  copy & share.
- **I7** A row's `resultUri` always names the file's current URI.
- **I8** A superseded result is parked before its plain name is reused.
- **I9** A replaced source keeps its date columns.

## 10. Anti-patterns

- **Scanning the results folder to decide what to act on.** The folder cannot
  attribute a file to a source; only a row can.
- **Writing the new result before parking the old one.** The insert takes
  `name (1).jpg`, and the "one result per source" promise becomes false.
- **Deleting the row before the file operation.** A failure then loses the only
  way to retry.
- **Using `sourceUri` as identity after a move.** A move can change the URI; the
  row must be rewritten, not assumed.
- **Recording any output regardless of folder.** Copy & share would pollute the
  batch table (see `recurrences.md`, R7).
- **Marking a row `applied` and keeping it.** A tombstone still renders, still
  counts as waiting in some queries, and still points at a file that may be
  gone.
- **Re-pinning the results folder after the user unpinned it.** The one-time
  claim is written before the pin for exactly this reason.

## 11. Where the code differs from the spec

- `BatchResultStatus.applied` and `.discarded` are rendered but never written;
  v1 deletes the row instead.
- The banner's "not now" dismissal is per widget instance, not persisted. The
  rows stay pending, which is the part that matters.
- `pruneSupersededFiles` only finds parked files the app's table already knows.
  A parked file the scanner never imported survives until the scanner sees it.
- Applying a profile writes only the rows the profile holds; a row the user
  enabled before choosing a profile keeps its state. From a fresh sheet, where
  every row starts disabled, the profile is the whole chain.
- The native executor and the EXIF copy have no host tests; `rules.md` marks
  those rows `-:` rather than pretending otherwise.
- Copy & share is specified (`FR-P1`, `FR-P2`) and not implemented.
