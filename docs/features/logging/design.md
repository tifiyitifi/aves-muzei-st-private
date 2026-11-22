# Fork logging — design

## The facade

`Log` is an `abstract final class` holding two pieces of state: the sink and the
gate table.

```text
call site ── AreaKeyLog(key) ──► Log.emit(key, level, message, error, stack)
                                     │
                            isEnabled(key, level)
                                     │  longest matching prefix of `key` in `_gates`
                                     ▼
                                  sink(key, level, message, error, stack)
```

The sink is a function type (`LogSink`), not an interface: swapping the transport
is assigning a function. The default sink calls `dart:developer` so DevTools
groups a record by channel name and severity; no logging package is involved.

## Gate resolution

`_gateFor(key)` takes the **longest** matching prefix, where a prefix matches if
it equals the key or the key continues past it with a dot. `log.db` therefore
covers `log.db.catalog`, and `log.db.catalog` can raise or lower its own. A key
with no matching prefix has the gate `off`.

`isEnabled` compares severities, so a `warning` gate passes `warning` and
`error`. `LogLevel.off` has a severity high enough to pass anything, which is
why `isEnabled` rejects it explicitly **before** the comparison: `off` is the
closed-channel sentinel and can never be a record level. Both sides of the
contract are tested (a closed channel must not leak the sentinel to the sink).

## Build defaults and the define

`applyDefaults(debug:)` clears the table, then:

1. debug builds seed every `LogKeys.all` entry at `verbose`;
2. `AVES_LOG_KEYS` is applied **last**, at `verbose` in debug and `warning`
   otherwise, so an explicit list wins over the build default.

`Log.init` calls `applyDefaults`, then opens the feature channels it was given
in debug builds only. Feature channels are deliberately not part of
`LogKeys.all`: a feature owns its key, the composition root subscribes to it.

## AreaKeyLog

A `const` wrapper holding one key and five leveled methods plus `log(level, ...)`.
It exists so a module writes `log.e('failed to open', error, stack)` and never
repeats the channel string at each call site; a typo in a key would otherwise
create a silently closed channel.

## Why not `debugPrint` or a package

- `debugPrint` cannot be gated per area, and in release it is usually stripped by
  the compiler, so a diagnostic that matters after release disappears.
- A logging package would add a dependency and a second configuration surface for
  behaviour this fork needs in about 180 lines; the sink seam already makes the
  transport replaceable.

## Anti-patterns

- Adding a fork channel to `LogKeys`: it makes every new feature edit the shared
  registry. Declare it in the slice.
- Calling `Log.emit` directly from a module that has an `AreaKeyLog`: the key then
  appears twice and can drift.
- Using `off` as a record level: it is the closed sentinel; `isEnabled` rejects it.
- Guarding with `isEnabled` and then emitting at a different level: the guard would
  answer for a level that is not the one emitted.
