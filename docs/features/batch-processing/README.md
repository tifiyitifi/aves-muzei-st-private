# Batch processing

Runs an ordered chain of image tools on a copy of each selected photo, records
every result, and offers to replace the original or move the result back.
Copy & share runs the same chain into a separate, temporary folder.

Status: **in progress**. The engine (`0bd4476aa`), the results workflow
(`3c827fe54`) and copy & share are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- one run over a collection or viewer selection, with a configurable tool chain;
- per-item isolation, partial completion and cancellation;
- a durable result record, and three decisions on a result: replace the
  original, move it back to the source folder, or leave it pending;
- saved action chains (profiles) reusable by a later run;
- a results folder that behaves like an app album;
- copy & share: the same chain into a temporary share folder, with its own
  retention and profiles, and no batch record.

Out of scope for v1:

- RAW development, markup, cut-out and video pixel work;
- undo/redo history for an applied result;
- automatic sharing, and any network step;
- a retention policy for batch results (only copy & share gets one);
- a dedicated results page for share output (the share album is the page).

## Version facts

| Fact | Value |
| --- | --- |
| Database schema | 17 (`batch_results`, `batch_profiles`; unchanged by copy & share) |
| Stream channel | `deckers.thibault/aves/batch_stream` |
| Method channel | `deckers.thibault/aves/batch` |
| Results folder | `Pictures/aves_batch_results` |
| Share folder | `Pictures/aves_share` |
| Share retention | off / 1 / 7 / 30 days, default 7 |
| Supersede suffix | `-to-remove` |
| Name pattern, replace previous | `{name}` |
| Name pattern, keep versions | `{name}_{date}` |
| Name pattern, copy & share | `{name}_{date}` |
| Entry points | collection multi-select action, viewer action, Settings › Batch |
| Settings page | `/settings/batch` |
| Results page | `/settings/batch/results` |
| Share settings page | `/settings/batch/share` |

## Reading order

1. `spec.md` — what the feature must do, as acceptance criteria.
2. `rules.md` — the case register; every row names the test that holds it.
3. `recurrences.md` — the complaints that return and the couplings behind them.
4. `design.md` — the pipeline, the data model and the invariants.
5. `decisions/` — why the judgement calls went the way they did.
6. `testing.md` — the gates a change has to pass.
7. `tasks.md` — what is still open.

Before changing behaviour, read `rules.md` and `recurrences.md` first: they say
which case the change is about and which coupling it can break. `design.md` then
says where the change belongs.

## Code map

| Layer | Path |
| --- | --- |
| Dart models | `lib/features/batch_ops/model/` |
| Dart stores | `lib/features/batch_ops/db/` |
| Dart services | `lib/features/batch_ops/services/` |
| Dart views | `lib/features/batch_ops/view/` |
| Native engine | `android/app/src/main/kotlin/deckers/thibault/aves/features/batch/` |
| Schema | `lib/features/drift_db/migration/migration_v17.dart` |
| Tests | `test/features/batch_ops/`, `test/features/drift_db/migration_v17_test.dart`, `test/utils/android_file_utils_test.dart` |
| L10n keys | `lib/l10n/app_en.arb` (`batch*`, `batchShare*`, `settingsBatch*`, `aboutKnownIssues5..7`) |

The feature is a self-contained slice: upstream trees only gain the action
entries (`lib/view/src/actions/`, `lib/widgets/collection/`, `lib/widgets/viewer/`),
the settings category and pages, one grid insertion and the album-type branches.

## Privacy note

Every path in this directory is a stand-in. A verification note describes the
kind of photo, never the file. See `docs/README.md`.
