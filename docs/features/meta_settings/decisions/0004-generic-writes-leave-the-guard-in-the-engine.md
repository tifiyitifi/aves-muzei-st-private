# 0004 — Generic writes leave the guard in the engine

Status: accepted.

## Context

The catalog is data: a def knows its key, how to read the value and which widget
edits it. Writing the value could either go through a typed setter per def or
through `SettingsAccess.set(key, value)`.

## Decision

Generic `toggle` and `enumPick` defs are written by `MetaSettingsEngine.apply`:
it validates with `MetaValueGuard`, then either calls the def's `mutator` (a
setter with internal side effects, such as the calendar locale cache) or
`SettingsAccess.set`. Enums persist by member name.

`custom` editors bypass the engine and call typed setters directly. They may
write several keys or perform async work, which a single validated value cannot
express.

## Consequences

- One validated write path for the majority of rows; the store never sees a value
  of the wrong type.
- A def never duplicates defaults: its `reader` reuses the app's typed getter.
- `custom` editors must own their validation; `value_guard_test` does not cover
  them.
- `apply` cannot report a persistence failure (the shared `SettingsAccess.set`
  contract). Interactive failures are documented in `design.md` as the accepted
  optimistic-value window; batch paths await `flush()`.
