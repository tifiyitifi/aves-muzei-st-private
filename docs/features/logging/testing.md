# Fork logging — testing

## What the host can drive

`test/features/logging/log_test.dart` replaces the sink with a recording closure
and drives the gate table directly. No platform channel and no transport is
involved, so the whole gating contract is host-testable:

- closed, enabled, disabled, explicit gate, parent and child gates, `only`;
- `isEnabled` (answers without emitting) and the `off` sentinel on both an open
  and a closed channel;
- sink forwarding of message, error and stack trace;
- `AreaKeyLog` channel and level routing;
- `AVES_LOG_KEYS` parsing and both build defaults;
- a feature channel opened through `Log.init(debugChannels: ...)`.

## What needs a device

- The Logcat mirror (CFG-5) branches on `kDebugMode`; a host run only reaches the
  debug branch, so the release mirror is verified by reading `_devSink` and by a
  manual check on a release build (`adb logcat | findstr "\[log\."`).
- DevTools grouping by channel name is a property of the default sink and is
  observed in DevTools, not asserted.

## Discipline

- A new channel key is declared in the owning slice, next to the code that logs;
  `LogKeys` gains an entry only for a genuinely cross-cutting area.
- A test that logs must set its own sink and reset the gates in `setUp`, so one
  file's gates do not leak into another's.
- `Log.reset()` in a tear-down is not needed when the sink and gates are set per
  test, but it is the safe default when a test calls `Log.init`.
