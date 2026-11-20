# Batch processing — specification

What the feature must do. Implementation detail lives in `design.md`; the case
register in `rules.md` maps every requirement to the test that holds it.

## Glossary

| Term | Meaning |
| --- | --- |
| **Source** | The user's original photo. A run never writes it. |
| **Result** | A file the run produced, always below the results folder. |
| **Run** | One job: an ordered tool chain over a selection. |
| **Result record** | The database row that says which source a result came from. |
| **Profile** | A saved, named action chain. |
| **Results folder** | `Pictures/aves_batch_results`, an app-owned album. |
| **Share copy** | A file a copy & share run produced, always below the share folder. |
| **Share folder** | `Pictures/aves_share`, an app-owned temporary folder. |

## Requirements

Each requirement is one observable behaviour. The acceptance criterion is written
as `WHEN <trigger>, THE SYSTEM SHALL <response>`; the `Rules:` line names the
register rows that hold it.

### FR-1 — A run writes only to the results folder

WHEN a user starts a batch run, THE SYSTEM SHALL write every output below the
results folder and SHALL NOT write any source file.

Rules: `RUN-1`.

### FR-2 — Only standard images are processed

WHEN the selection contains videos or RAW files, THE SYSTEM SHALL drop them
before the job is built and SHALL run only on standard images.

Rules: `RUN-2`.

### FR-3 — The chain runs in the order the user arranged

WHEN several tools are enabled, THE SYSTEM SHALL apply them in the sheet's order
in one decode and one encode per image.

Rules: `RUN-3`, `RUN-7`, `RUN-8`.

### FR-4 — A failure is isolated to its item

WHEN one item fails, THE SYSTEM SHALL report it and SHALL continue with the next
item.

Rules: `RUN-5`.

### FR-5 — Cancellation keeps what is already written

WHEN a run is cancelled, THE SYSTEM SHALL keep every result already written and
SHALL report the remaining items as failed or cancelled.

Rules: `RUN-4`.

### FR-6 — Every finished item becomes a record

WHEN the native side reports a finished item, THE SYSTEM SHALL record its
source, the name, path, size and MIME type the MediaStore assigned, and the
action chain that produced it.

Rules: `REC-1`, `REC-3`, `REC-5`.

### FR-7 — Only the results folder is recorded

WHEN a run writes outside the results folder, THE SYSTEM SHALL NOT record its
output as a batch result.

Rules: `REC-4`, `CLS-4`.

### FR-8 — A result carries the source's metadata

WHEN a result is written, THE SYSTEM SHALL copy the source's capture time,
camera and location metadata onto it.

Rules: `RUN-9`, `APP-3` (a later replacement must preserve them).

### FR-9 — A repeat run keeps one pending result by default

WHEN the same source is processed again in replace-previous mode, THE SYSTEM
SHALL leave exactly one pending result and SHALL give it the source's plain
name.

Rules: `REP-1`, `REP-4`.

### FR-10 — Keep-versions keeps every result

WHEN keep-versions is selected, THE SYSTEM SHALL name each result
`{name}_{date}` and SHALL keep every version pending.

Rules: `REP-3`.

### FR-11 — Replace overwrites the original in place

WHEN the user confirms replace, THE SYSTEM SHALL overwrite the source bytes in
place, keep the source's date columns, update the source name and MIME type when
the format changed, and consume the result file.

Rules: `APP-1`, `APP-3`.

### FR-12 — A failed replacement keeps the result actionable

WHEN a replacement fails, THE SYSTEM SHALL keep the result pending so it can be
retried or moved back.

Rules: `APP-2`.

### FR-13 — Move back never overwrites

WHEN the user confirms move back, THE SYSTEM SHALL move the result into the
directory its source came from and SHALL rename it on a name conflict.

Rules: `APP-5`, `APP-6`.

### FR-14 — Write access is requested once per batch

WHEN a replacement needs scoped-storage write access, THE SYSTEM SHALL request
it once for the whole selection before the first write.

Rules: `APP-4`.

### FR-15 — The results UI offers no delete action

THE SYSTEM SHALL NOT offer a delete action in the batch results UI.

Rules: `UI-1`.

### FR-16 — A vanished result loses its row

WHEN the results page or the banner opens, THE SYSTEM SHALL drop every row whose
result file no longer exists.

Rules: `HOU-1`, `HOU-3`.

### FR-17 — The results folder is an app album, pinned once

WHEN the results folder is listed, THE SYSTEM SHALL classify it as an app album.
WHEN the first run records a result, THE SYSTEM SHALL pin the folder once per
install.

Rules: `CLS-1`, `CLS-7`, `CLS-6`.

### FR-18 — Profiles are reusable action chains

WHEN the user saves a profile, THE SYSTEM SHALL persist the chain with its
disabled rows. WHEN a later run starts from a profile, THE SYSTEM SHALL apply
that profile's saved rows to the matching tools.

Rules: `PRF-1` … `PRF-7`.

### FR-19 — The results page supports the app-wide range gesture

WHEN the user long-presses a result after tapping another, THE SYSTEM SHALL
apply the shared XOR-range rule to the results list.

Rules: `UI-3`.

### FR-20 — Copy & share reuses the engine and records nothing

WHEN the user starts copy & share, THE SYSTEM SHALL run the same tool chain as a
batch run, write every copy below the share folder, and SHALL NOT record the
output in the batch results table.

Rules: `SHR-1` … `SHR-8`.

### FR-21 — Share output has a retention policy

WHEN a share copy is older than the configured retention, THE SYSTEM SHALL
delete it without touching a batch result, a source, or a copy exactly at the
cutoff.

Rules: `SHR-9` … `SHR-16`.

### FR-22 — The share explainer is shown once and offers settings

WHEN the user starts copy & share for the first time on an install, THE SYSTEM
SHALL explain the temporary folder and SHALL offer its settings before the run.

Rules: `SHR-18`, `SHR-20`.

### FR-23 — Share profiles are separate from batch profiles

WHEN the share sheet or the share settings page opens, THE SYSTEM SHALL offer
only share profiles and SHALL seed one default share profile.

Rules: `PRF-1`, `PRF-2`, `SHR-17`.

### FR-24 — A share run ends at the share album

WHEN a share run finishes, THE SYSTEM SHALL offer to open the share album and
SHALL NOT open a system share sheet automatically.

Rules: `SHR-19`.

## Non-goals

- Editing pixels of a source during a run.
- RAW development, markup, cut-out, or video processing in batch.
- Undo/redo of an applied result.
- Automatic sharing or any network step.
- A retention policy for batch results (only copy & share gets one).
- A dedicated results page for share output: the share album is the page, and
  share output has no replace or move-back decision.
