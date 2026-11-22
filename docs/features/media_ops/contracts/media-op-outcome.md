# Media operation outcome — channel contract

The native fast pipeline and Dart exchange one event per entry. This file is the
contract between `MediaOpV2` (Kotlin) and `MoveOpEvent` (Dart); changing a key or
a value here means changing both sides and `media_op_outcome_test.dart`.

## Event shape

| Key | Type | Meaning |
| --- | --- | --- |
| `success` | `bool` | the entry was moved/renamed |
| `skipped` | `bool` | the entry was already at the target (counted as success) |
| `uri` | `String` | the source URI the caller sent |
| `newFields` | `Map` | the facts the platform assigned: `uri`, `path`, `sizeBytes`, `mimeType` |
| `deleted` | `bool` | the source was removed (move, not copy) |
| `permission` | `String?` | `granted`, `denied`, `unavailable`, or absent for the legacy pipeline |
| `strategy` | `String?` | `mediastore`, `file`, `saf`, or absent for the legacy pipeline |

`MoveOpEvent.fromMap` also accepts `skipped`/`deleted` inside `newFields`, because
the native side reports both shapes.

## Values

### `strategy`

| Value | Meaning |
| --- | --- |
| `mediastore` | the row was updated in place; no scan was needed |
| `file` | the file was moved directly and the stale row was cleared |
| `saf` | a SAF copy was written and the source was removed |

The plan is chosen before any write by `MediaOpPlan.selectMoveApi` (see
`rules.md` PLAN-1..PLAN-4). A `strategy` that does not match the plan means the
fallback ran; that is expected and must be reported, not hidden.

### `permission`

| Value | Meaning | Dart reaction |
| --- | --- | --- |
| `granted` | the write request was approved | nothing is remembered; a successful move already proves it |
| `denied` | the user refused the request | `recordMediaOpOutcome` remembers the denial in `MediaOpPrefs` |
| `unavailable` | no request could be made (disabled, no Activity, API below 30, too many URIs) | nothing is remembered |

`permission` is reported at most once per operation. The legacy pipeline leaves
it null; Dart must treat null as "no opinion", not as a denial.

## Invariants

1. A denial anywhere in a batch wins over any grant: one remembered answer is
   enough to stop asking.
2. A grant is never persisted. The OS can revoke access on its own.
3. `strategy` and `permission` are optional; a consumer that only needs the new
   location must not require them.
4. `newFields.uri` is the only reliable new identity. `path` may be empty when
   the platform has not filled `DATA` yet; callers fall back to the URI.

## Where it is read

- `lib/features/media_ops/media_op_outcome.dart` — remembers a denial.
- `lib/widgets/common/action_mixins/entry_storage.dart` — applies the moved
  fields and the deletion.
- `lib/features/refra_edit/services/refra_edit_service.dart` — rewrites an
  output's location after a copy back.
