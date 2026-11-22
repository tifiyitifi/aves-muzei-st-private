# Collection paging — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| Host test for `albumActionUsesDatabase` and `pagedScopeUnsupported` | the guard is the only thing standing between a paged library and a silent no-op action, and it has no test | `LEN-36` (currently unfalsified) |
| Host test for the trash exemption and the summary complement together | the two are covered separately; their interaction is only exercised on a device | `GAT-3` (visible_range) |
| Migration tests for the wallpaper-group and edit-session schema steps (v7, v8, v10–v15) | `AGENTS.md` requires an upgrade test per schema step; the paged database grew through them | `AGENTS.md` persistence rules |
| Decide whether a first import should be cancellable from the browse-only bar | today it resumes on the next launch instead | `IMP-1`, `PHS-5` |
| Replace the remaining `debugPrint` calls in the collection paths with the fork logger | the fork logging rule asks new code to use `lib/features/logging/` | `C1` (recurrences) |

Not planned: a second database schema for paged rows. The paged path reads the
same tables the legacy path fills, so a scope can switch engines without a
migration.
