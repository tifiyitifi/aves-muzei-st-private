# Media operations — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-media-ops-rules.ps1` resolves every `F:` token.

## Engine

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| ENG-1 | Default engine | WHEN no value is stored, THE SYSTEM SHALL use the fast pipeline | `2afb33613` | `F:media_op_engine_test#defaults to the fast pipeline`; `F:media_op_prefs_test#starts on the fast pipeline and allows one prompt` |
| ENG-2 | Member round-trip | WHEN an engine name is stored and read, THE SYSTEM SHALL keep the same member | `2afb33613` | `F:media_op_engine_test#tryParse round-trips member names` |
| ENG-3 | Unknown engine | WHEN the stored name is not a known member, THE SYSTEM SHALL reject it and fall back | `2afb33613` | `F:media_op_engine_test#tryParse rejects unknown and null`; `F:media_op_prefs_test#falls back to defaults on unknown values` |

## Plan

The native planner (`MediaOpPlan`) decides the API before any write. Its unit
tests live next to the Kotlin source, so their coverage is recorded as `-:native`
with the test name.

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| PLAN-1 | Row beats file access | WHEN an entry is a Media Store row, source and target share a volume and the target directory is allowed, THE SYSTEM SHALL update the row even when both sides grant file access | renaming the file would need a scan | `-:native MediaOpPlanTest#sameVolumeRowMoveBeatsDirectFileAccess` |
| PLAN-2 | Media Store preconditions | WHEN the move is cross-volume, the target is not allowed, the operation is a copy, or the API is below 29, THE SYSTEM SHALL not choose the row path | `RELATIVE_PATH` moves need Android 10 and copies keep SAF | `-:native MediaOpPlanTest#mediaStoreMoveNeedsSameVolumeAndAllowedDirectory` |
| PLAN-3 | File copy floor | WHEN access is mixed and the operation is a copy, THE SYSTEM SHALL use direct file copy only from Android 11 | an older platform cannot write the foreign side directly | `-:native MediaOpPlanTest#directFileCopyIsAllowedOnApi30WithMixedAccess` |
| PLAN-4 | SAF fallback | WHEN neither side can be written directly, THE SYSTEM SHALL fall back to SAF | the last resort must stay reachable | `-:native MediaOpPlanTest#missingOrSafAccessFallsBackToSaf` |
| PLAN-5 | Prompt preconditions | WHEN a write request is considered, THE SYSTEM SHALL require consent, Android 11, a ready Activity and a non-empty selection within the bulk limit | a request that cannot be shown would fail the batch | `-:native MediaOpPlanTest#promptNeedsConsentForegroundActivityAndBulkApi` |
| PLAN-6 | Native engine parse | WHEN the native side parses an unknown engine name, THE SYSTEM SHALL fall back to the fast pipeline | the same default as the Dart side | `-:native MediaOpPlanTest#engineParsingFallsBackToTheFastPipeline` |

## Outcomes and permissions

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| OUT-1 | Optional fields | WHEN the fast pipeline reports a move, THE SYSTEM SHALL carry `permission` and `strategy` | `2afb33613` | `F:media_op_outcome_test#reads the optional outcome fields` |
| OUT-2 | Legacy fields | WHEN the legacy pipeline reports a move, THE SYSTEM SHALL leave the new fields null | `2afb33613` | `F:media_op_outcome_test#leaves the outcome fields null for the legacy pipeline` |
| OUT-3 | Denial remembered | WHEN any event reports `denied`, THE SYSTEM SHALL remember the denial | `2afb33613` | `F:media_op_outcome_test#remembers a denial`; `F:media_op_outcome_test#a denial anywhere in the batch wins` |
| OUT-4 | Grants do not stick | WHEN the outcome is `granted` or `unavailable`, THE SYSTEM SHALL not change the remembered answer | `2afb33613` | `F:media_op_outcome_test#ignores grants and unavailable requests` |
| OUT-5 | Reset | WHEN the user resets the permission state, THE SYSTEM SHALL allow a prompt again | `2afb33613` | `F:media_op_prefs_test#reset re-enables prompts after a denial` |
| OUT-6 | Notify once | WHEN a value does not change, THE SYSTEM SHALL not notify listeners | `2afb33613` | `F:media_op_prefs_test#notifies listeners only on actual change` |

## File safety

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SAFE-1 | Source opened first | WHEN a SAF copy starts, THE SYSTEM SHALL open the source before creating the target | a null stream used to create an empty target and delete the source | `-:native MediaOpV2, no host fixture` |
| SAFE-2 | Same-volume move | WHEN source and target share a volume, THE SYSTEM SHALL update the row in place | `239ea4a40` | `F:media_op_outcome_test#reads the optional outcome fields`; `-:native MediaOpPlanTest#sameVolumeRowMoveBeatsDirectFileAccess`; `M` |
| SAFE-3 | Stale row cleared | WHEN a file fallback moved the file, THE SYSTEM SHALL clear the old row even if the direct delete is refused | `239ea4a40` | `M` |
| SAFE-4 | One refusal is local | WHEN a row update is refused, THE SYSTEM SHALL not disable the row path for unrelated entries | a temporary `REFUSED` is not `UNSUPPORTED` | `-:native MediaOpV2, no host fixture` |
| SAFE-5 | Strategy reported | WHEN a move finishes, THE SYSTEM SHALL report which API served it | the next operation and the diagnostics depend on it | `F:media_op_outcome_test#reads the optional outcome fields`; `-:native MediaOpV2, no host fixture` |
