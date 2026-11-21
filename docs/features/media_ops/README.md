# Media operations

Moves, copies and renames media entries through the cheapest storage API the
platform allows: a same-volume Media Store row update, a direct file operation,
or a SAF document operation, in that order.

Status: **in progress**. The fast pipeline (`2afb33613`) and the single-row move
(`239ea4a40`) are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- one move/copy/rename request over a collection or viewer selection;
- per-entry API choice, resolved once per directory;
- scoped-storage write access requested once per batch, with the answer
  remembered;
- a batched scanner pass only for entries the fast paths cannot update.

Out of scope:

- delete (it stays on the legacy pipeline);
- cross-app or network transfers;
- undo history.

## Version facts

| Fact | Value |
| --- | --- |
| Engine gate | `media_ops.engine` (`v1` legacy, `v2` fast) |
| Move strategies | `mediastore`, `file`, `saf` |
| Permission cache | `MediaOpPrefs` (`granted`, `denied`, `unavailable`) |
| Write request limit | 2000 URIs per `MediaStore.createWriteRequest` |
| Entry points | collection multi-select move/copy/rename, album rename, refra_edit, batch move-back |

## Reading order

1. `spec.md` — what the feature must do.
2. `rules.md` — the case register; every row names its evidence.
3. `decisions/` — why the fallback order is what it is.
4. `testing.md` — gates, fixtures and the device checks.

## Code map

| Layer | Path |
| --- | --- |
| Dart setting | `lib/features/media_ops/model/media_op_engine.dart`, `engine/media_op_prefs.dart` |
| Dart permission outcome | `lib/features/media_ops/media_op_outcome.dart` |
| Native fast pipeline | `android/app/src/main/kotlin/deckers/thibault/aves/features/media_ops/` |
| Legacy providers | `android/app/src/main/kotlin/deckers/thibault/aves/model/provider/` |
| Tests | `test/features/media_ops/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
