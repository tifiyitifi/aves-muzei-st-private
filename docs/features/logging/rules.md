# Fork logging — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-logging-rules.ps1` resolves every `F:` token.

## Gating

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| GAT-1 | Closed channel | WHEN a channel is closed, THE SYSTEM SHALL emit nothing | a release build must stay silent until asked | `F:log_test#emits nothing while a channel stays closed` |
| GAT-2 | Enable and disable | WHEN a channel is enabled at runtime, THE SYSTEM SHALL pass every level; WHEN disabled, SHALL pass nothing | runtime control is the point of the facade | `F:log_test#setEnabled(true) opens a channel for every level`; `F:log_test#setEnabled(false) closes a channel again` |
| GAT-3 | Explicit gate | WHEN a gate is set to a level, THE SYSTEM SHALL pass only records at or above it | an open channel may still be noisy | `F:log_test#setLevel raises the gate` |
| GAT-4 | Parent gate | WHEN a parent channel is open, THE SYSTEM SHALL apply its gate to children that define none | opening `log.db` must not need every child listed | `F:log_test#a parent gate applies to child channels` |
| GAT-5 | Child override | WHEN a child defines its own gate, THE SYSTEM SHALL use it over the parent's | the longest prefix is the most specific decision | `F:log_test#a child gate overrides its parent` |
| GAT-6 | Exclusive open | WHEN `only` is called, THE SYSTEM SHALL close every other channel | narrowing a noisy session must not leave stragglers | `F:log_test#only() closes every other channel` |
| GAT-7 | Query without emit | WHEN `isEnabled` is asked, THE SYSTEM SHALL answer without emitting | callers guard expensive message construction with it | `F:log_test#isEnabled reports the gate without emitting` |
| GAT-8 | Off sentinel | WHEN the requested level is `off`, THE SYSTEM SHALL never emit it | `off` is a gate value, not a record level | `F:log_test#never reports the off sentinel as enabled, even on an open channel`; `F:log_test#a closed channel does not leak the off sentinel to the sink` |

## Sink and call sites

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SINK-1 | Record forwarding | WHEN a record passes the gate, THE SYSTEM SHALL forward message, error and stack trace unchanged | a sink that rewrites a record breaks diagnosis | `F:log_test#forwards message, error and stack trace` |
| AREA-1 | Area logger | WHEN `AreaKeyLog` logs, THE SYSTEM SHALL use its channel and the method's level | the key is declared once per module | `F:log_test#routes to its channel and level` |

## Configuration

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| CFG-1 | Key list parsing | WHEN `AVES_LOG_KEYS` is parsed, THE SYSTEM SHALL split on commas and drop blanks | a hand-edited define must not open an empty channel or lose an entry | `F:log_test#splits on commas, trimming blanks`; `F:log_test#returns empty for blank input` |
| CFG-2 | Debug default | WHEN the build is debug, THE SYSTEM SHALL open every shared channel at `verbose` | development logs must not be silently dropped | `F:log_test#opens every channel in debug` |
| CFG-3 | Release default | WHEN the build is release, THE SYSTEM SHALL open nothing by default | nothing is logged unless the build asks for it | `F:log_test#opens nothing in release` |
| CFG-4 | Feature channels | WHEN the composition root passes feature channels, THE SYSTEM SHALL open them in a debug build | a feature adds logging without editing the shared registry | `F:log_test#a feature channel can be opened by the composition root` |
| CFG-5 | Logcat mirror | WHEN a release build emits a warning or an error, THE SYSTEM SHALL mirror it to Logcat with its channel | the developer transport is not surfaced in release | `-:the mirror branches on kDebugMode, so a host test can only exercise the debug branch (see testing.md)` |

## Policy

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| KEY-1 | Channel ownership | WHEN a channel is added, THE SYSTEM SHALL declare it in the owning slice, and SHALL keep only cross-cutting channels in `LogKeys` | a shared catch-all makes every logging change a shared-file edit | `-:a declaration convention enforced in review, not a runtime behaviour` |
