# Metadata settings engine — design

## One store, chosen before anything reads

```
SharedPreferences ──► SettingsEngineGate (key `settings_engine`)
                             │
                             ▼
              SettingsStoreRouter ──► SharedPrefSettingsStore (v1)
                    │        │
                    │        └─────► MetaSettingsStore (v2) ──► settingsValues (Drift)
                    │
                    └──► SettingsAccess (`settings.*`) ──► app + v2 surface
```

`SettingsStoreRouter` is the only store the app sees. `SettingsAccess` keeps its
typed getters and setters, so no caller knows which engine answered. The gate is
read once in `init` and committed on `activate`.

## Why the gate lives outside both stores

The gate must be readable *before* a store is chosen, and it must survive both
engines' `clear()`. `SharedPreferences` is the only place that satisfies both,
because v1 *is* `SharedPreferences`. The router therefore treats the key as
outside the settings key space: reads return null, `getKeys` filters it,
`remove` is a no-op, `clear` re-asserts it, and writes are ignored. Without that
last part, a legacy-engine session would write the gate into its own file and
silently change the next launch's engine.

## The metadata store is sparse overrides

`settingsValues` holds only keys that differ from the app defaults; a missing row
means "use `SettingsDefaults`". Each row stores the value with a self-describing
`type` tag, so a getter never guesses. A row whose tag is unreadable is skipped
and logged rather than failing the whole load.

Values are cached at `init` so the typed getters stay synchronous, like
`SharedPreferences`. Writes update the cache and persist asynchronously; a failed
write re-syncs the cache from the database. The one accepted imperfection: a
listener that already applied an optimistic value keeps it until the next reload,
because `SettingsAccess.set` publishes synchronously and drops the store's
future. Batch paths avoid it by awaiting `flush()`.

## Seeding is one-shot but resumable

`MetaSettingsSeeder` runs when v2 becomes authoritative and the `appMeta` marker
is absent. It iterates the legacy store's keys, skips the gate and transient
internal state, and copies whatever v2 does not already have. The marker is
written only after a complete pass, so an interrupted seed resumes; already
copied keys are never overwritten, which keeps a retry from resurrecting a value
the user changed in v2 in the meantime.

## Switching is a state transition, not a preference write

`activate` initializes the incoming store *first*. Only then does it persist the
gate. This order means a failed database open or a failed gate write leaves the
gate, the version field and the active store all on the old engine — the app
never points at a half-open store.

After a successful switch, `SettingsEngineController` replays the diff between the
two stores key by key. This is not cosmetic: listeners that cache a value
(brightness, refresh rate, layout, locale) have already read the old engine, and
without the replay they would keep it until restart. Replayed keys are marked
`recordRecent: false`, so one switch does not flood the "recently changed"
suggestions.

## The catalog is the v2 surface

A `SettingDef` declares the key (`SettingKeys` constant, compile-checked), the
title (`context.l10n`, compile-checked), how to read the value, and how to edit
it. The renderer dispatches on `SettingWidgetKind`; `custom` editors and
`subPage` routes are looked up by key in registries, never imported by the
catalog. `validateMetaSettingsCatalog` rejects duplicate keys and a def missing
the field its kind needs, and the release gate runs it in a test.

`MetaSettingsEngine.apply` is the write path for generic defs. It validates with
`MetaValueGuard`, then either calls the def's `mutator` (for setters with
internal side effects) or `SettingsAccess.set`. Enums are persisted by name.
`custom` editors call typed setters directly and bypass the guard by design,
because they may write several keys or run async work.

## Anti-patterns

- **Reading the gate through `settings`.** It is not a setting; use
  `SettingsEngineGate`.
- **Writing a def with a typed setter when a generic one exists.** The reader
  would no longer match the store's value.
- **Seeding on every v2 init.** The marker is what keeps a deliberate v2 reset
  from resurrecting v1.
- **Committing the switch before the incoming store opens.** It produces a gate
  that names a store the app cannot read.
- **Replaying with `recordRecent: true`.** A switch would mark every differing
  key as a user edit.
