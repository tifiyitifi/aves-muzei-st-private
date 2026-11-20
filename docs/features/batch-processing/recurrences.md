# Batch processing — what comes back

`rules.md` says what the feature must do. This file says **how the rule set
fails**: the complaints that return, and the couplings that make fixing one of
them break another.

Two readings:

- **R** — a symptom a user can report. Each one has a mechanism, a rule that now
  holds it, and a condition under which it returns.
- **C** — a coupling: one input read by several subsystems, so a change aimed at
  one of them lands in all of them.

A change is not finished until it says which R it is about and which C it
touches. `decisions/` records the ones that needed a judgement, not a fix.

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | A rerun leaves `name (1).jpg` beside the result | The new result was inserted while the old one still held the plain name | `REP-1`: park, delete, then rename | A writer inserts a result before superseding the old one | `3c827fe54` |
| R2 | A result deleted from the album still offers "replace original" | A deleted file leaves nothing for the change cursor, so the result row outlives its file | `HOU-1`: reconcile on page and banner open | A new surface reads rows without reconciling first | `25a3f5a19`, `3c827fe54` |
| R3 | A replaced original loses capture time and location | Re-encoding drops EXIF | `RUN-9`, `FR-8`: the bake runner copies the source's tags onto the result | A new output path writes bytes without the EXIF copy | `3c827fe54` |
| R4 | A PNG result is still named `.jpg` | The bytes were replaced but the source row kept its name and MIME | `APP-3`: update name and MIME when the format changed | A writer replaces bytes only | `3c827fe54` |
| R5 | A cancelled run "loses" the photos it finished | Rows were written only when the whole job ended | `REC-1`: record on `itemDone` | Recording moves back to `jobDone`, or a caller does not await `recordsSettled` | `0bd4476aa`, `3c827fe54` |
| R6 | Replace fails silently on Android 11+ | Scoped storage refuses the write until the user grants access | `APP-4`: one write request before the batch | A new caller writes without requesting access | `3c827fe54`, `2afb33613` |
| R7 | Copy & share output appears in the batch results table | The recorder accepted any output | `REC-4`, `CLS-4`: the output relative path must be the results folder | The gate is relaxed to "any image output" | `3c827fe54` |
| R8 | The results album is not in the album list after the first run | The folder was never pinned, so the collection source never listed it | `CLS-6`: claim the pin once, before pinning | The pin is moved after an await that can fail, or the claim is not written | `3c827fe54` |
| R9 | A `-to-remove` file stays visible | The cleanup was interrupted between the rename and the delete | `HOU-2`: prune parked files after a run | The rename/delete sequence changes, or the prune is removed | `3c827fe54` |
| R10 | A profile's action has no row in the run sheet | The sheet owns one row per runnable tool; a kind the sheet does not offer is ignored | `PRF-5`, `PRF-7`: join on kind, drop what is unknown | A tool is added natively without a catalog entry, or the catalog shrinks | `3c827fe54` |
| R11 | A moved result keeps a URI that no longer resolves | A move can give the file a new MediaStore id | `REC-8`: rewrite the row after the transfer | A move path skips `_syncAfterTransfer` | `239ea4a40`, `3c827fe54` |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | `sourceUri` | record, supersede, replace, move back, write-access request | Change what a reader does with it, never what it means. A move can invalidate it; the row's source is a snapshot, not a live identity | `3c827fe54` |
| C2 | `resultUri` | thumbnail lookup, replace, move back, rename, prune | Always rewrite it through `updateResultLocation` after a rename or move; never cache it across a file operation | `3c827fe54` |
| C3 | `BatchOutput.relativePath` | run sheet, native output spec, recorder gate, future copy & share | Keep the gate exact: batch is `Pictures/aves_batch_results`, share is another folder | `3c827fe54` |
| C4 | The results path | Dart constant, Kotlin default, ARB label, album classification, pin filter | Change `batchResultsRelativeRoot` and the native default together; the ARB label is display text and must match | `3c827fe54` |
| C5 | `itemDone` | progress counters, last-output display, recorder queue | Add fields, never move recording to another event; the queue is what keeps rows in item order | `3c827fe54` |
| C6 | `_syncAfterTransfer` | rename (supersede) and move (move back) | Treat both as a transfer: update the row when the id survives, insert and drop otherwise | `3c827fe54`, `e6c76c8f1` |
| C7 | `status` | `getPending`, `getPendingBySource`, prune, banner count | Only `pending` is written in v1; a new value needs a query audit, not just a column write | `3c827fe54` |
| C8 | `batchSettings` | recorder, run sheet, settings page | Keep the injectable override for tests; the process-wide instance is for the app | `3c827fe54` |
| C9 | Profile `kind` | profile store, run sheet, settings page, future share entry | The kind is the join key; a new run kind adds rows, not a table | `3c827fe54` |
