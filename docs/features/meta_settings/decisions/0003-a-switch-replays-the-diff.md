# 0003 — A switch replays the diff before the surface swaps

Status: accepted.

## Context

Several settings are cached by their consumers (brightness, refresh rate, layout,
locale). They react to `settings.updateStream` rather than re-reading on every
frame. Swapping the store therefore changes what the getters answer without
notifying anyone: the surface repaints with the new engine while the running app
keeps the old behaviour.

## Decision

After `SettingsStoreRouter.activate` commits the switch, `SettingsEngineController`
walks the union of both stores' keys, skips the gate, and calls
`notifyKeyChange(key, oldValue, newValue, recordRecent: false)` for every key
whose value differs. It then resets the locale cache, sanitizes the settings,
and notifies its own listeners so `SettingsHost` swaps the surface.

## Consequences

- Cached consumers re-apply the authoritative values immediately.
- The replay is not a user edit, so it does not pollute the recent-changed list
  that search uses for suggestions.
- A key present in only one store still replays, because its other side is null.
