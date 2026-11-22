# Metadata settings engine — testing

The engine has no platform channel: every rule is falsifiable on the host. That
is why `rules.md` contains only one unfalsified row (`INIT-6`, whose steps are
covered separately).

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Host tests | `.flutter/bin/flutter.bat test test/features/meta_settings` | do the gate, store, seed, catalog and engine rules hold |
| Rule register | `pwsh -NoProfile -File scripts/check-meta-settings-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does the switch reach the running UI |

## Fixtures

- `test/features/meta_settings/settings_store_router_test.dart` drives the router
  with an in-memory database and the in-memory `SharedPreferences` fake from
  `test/common.dart`.
- `meta_settings_store_test.dart` covers the cache, the failure path and
  `flush()`.
- `meta_settings_engine_test.dart` pins the generic write path: a toggle, a
  rejected value and an enum persisted by name.
- `catalog_test.dart` is the release gate for the catalog: it validates every def
  and every category's migration coverage.

Database tests need a full native sqlite3 on Windows; see `AGENTS.md` for
`AVES_SQLITE3_DLL`.

## Device checklist

1. Switch Advanced › engine to v1 and back. Expect the surface to repaint in
   place, brightness and refresh-rate behaviour to follow the newly authoritative
   values without a restart. (`INIT-4`, `INIT-6`)
2. Restart the app on v1, switch to v2. Expect the settings to keep their values
   rather than reset to defaults. (`SEED-1`)
3. Clear all settings, then restart. Expect the engine choice to survive the
   clear. (`GATE-5`)
4. Enable a v2-only toggle, switch to v1, then back. Expect the v2 value to
   return, proving the stores stayed independent. (`SEED-3`)

## Privacy

Describe settings by category, never by a real value that reveals a local path or
media title.
