# Batch processing

Runs an ordered chain of image tools on a copy of each selected photo, records
every result, and offers to replace the original or move the result back.

Status: **in progress**. The engine (`0bd4476aa`) and the results workflow
(`3c827fe54`) are on `avest-dev`; copy & share is the next step and is not
implemented.

## Scope

In scope:

- one run over a collection or viewer selection, with a configurable tool chain;
- per-item isolation, partial completion and cancellation;
- a durable result record, and three decisions on a result: replace the
  original, move it back to the source folder, or leave it pending;
- saved action chains (profiles) reusable by a later run;
- a results folder that behaves like an app album.

Out of scope for v1:

- RAW development, markup, cut-out and video pixel work;
- undo/redo history for an applied result;
- automatic sharing, and any network step;
- a retention policy for results (copy & share will add one for its own kind).

## Version facts

| Fact | Value |
| --- | --- |
| Database schema | 17 (`batch_results`, `batch_profiles`) |
| Stream channel | `deckers.thibault/aves/batch_stream` |
| Method channel | `deckers.thibault/aves/batch` |
| Results folder | `Pictures/aves_batch_results` |
| Supersede suffix | `-to-remove` |
| Name pattern, replace previous | `{name}` |
| Name pattern, keep versions | `{name}_{date}` |
| Entry points | collection multi-select action, viewer action, Settings › Batch |
| Settings page | `/settings/batch` |
| Results page | `/settings/batch/results` |

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
| Tests | `test/features/batch_ops/`, `test/features/drift_db/migration_v17_test.dart` |
| L10n keys | `lib/l10n/app_en.arb` (`batch*`, `settingsBatch*`, `aboutKnownIssues5..7`) |

The feature is a self-contained slice: upstream trees only gain the action
entries (`lib/view/src/actions/`, `lib/widgets/collection/`, `lib/widgets/viewer/`),
the settings category, one grid insertion and one album-type branch.

## Privacy note

Every path in this directory is a stand-in. A verification note describes the
kind of photo, never the file. See `docs/README.md`.
