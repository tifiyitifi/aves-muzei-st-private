# 0001 — The gate is not a setting

Status: accepted.

## Context

The app needs one answer to "which settings store is authoritative". The value
has to be readable before either store is initialized, and it has to survive a
settings reset, because resetting settings must not silently change the engine on
the next launch.

## Decision

The selector lives in `SharedPreferences` under `settings_engine`, read and
written by `SettingsEngineGate` only. The router treats the key as outside the
settings key space:

- `getKeys()` filters it, and every getter returns null for it;
- `remove` and every setter ignore it;
- `clear()` re-asserts the stored value and reports a failed re-assert.

## Consequences

- Reset, export and import never see or move the selector.
- A legacy-engine session cannot overwrite the gate, even though it uses the same
  `SharedPreferences` file.
- Any future settings backend must keep this one key outside its own storage, or
  the router must grow a second exception.
