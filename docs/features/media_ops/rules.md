# Media operations — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-media-ops-rules.ps1` resolves every `F:` token.

## Engine

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| ENG-1 | Default engine | WHEN no value is stored, THE SYSTEM SHALL use the fast pipeline | `2afb33613` | `F:media_op_engine_test#defaults to the fast pipeline`; `F:media_op_prefs_test#starts on the fast pipeline and allows one prompt` |
| ENG-2 | Member round-trip | WHEN an engine name is stored and read, THE SYSTEM SHALL keep the same member | `2afb33613` | `F:media_op_engine_test#tryParse round-trips member names` |
| ENG-3 | Unknown engine | WHEN the stored name is not a known member, THE SYSTEM SHALL reject it and fall back | `2afb33613` | `F:media_op_engine_test#tryParse rejects unknown and null`; `F:media_op_prefs_test#falls back to defaults on unknown values` |

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
| SAFE-2 | Same-volume move | WHEN source and target share a volume, THE SYSTEM SHALL update the row in place | `239ea4a40` | `M` |
| SAFE-3 | Stale row cleared | WHEN a file fallback moved the file, THE SYSTEM SHALL clear the old row even if the direct delete is refused | `239ea4a40` | `M` |
| SAFE-4 | One refusal is local | WHEN a row update is refused, THE SYSTEM SHALL not disable the row path for unrelated entries | a temporary `REFUSED` is not `UNSUPPORTED` | `-:native MediaOpV2, no host fixture` |
