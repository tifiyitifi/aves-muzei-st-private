# Metadata settings engine (v1 / v2)

A second settings engine that stores sparse overrides in the app database, plus
the switch that decides which engine is authoritative. The upstream settings
model and settings UI (v1) stay untouched; the fork adds the store, the gate and
the catalog-driven v2 surface.

Status: **in progress**. The engine, the one-time seed and the catalog surface
are on `avest-dev`; nothing is released yet.

## Scope

In scope:

- one authoritative settings store, selected by a persisted gate;
- a Drift-backed store whose rows are sparse overrides over the app defaults;
- a one-time copy of the legacy settings into an empty v2 store;
- an immediate, rollback-safe engine switch;
- a declarative catalog that drives the v2 settings surface;
- a fork-owned settings page set that renders the catalog.

Out of scope:

- changing the upstream `Settings` model or its typed setters;
- migrating settings between installs (export/import is upstream and engine
  agnostic);
- a second global-state mechanism: the v2 surface reads through the same
  `settings` singleton.

## Version facts

| Fact | Value |
| --- | --- |
| Gate key | `settings_engine` in `SharedPreferences` |
| Gate values | `v1` (upstream store), `v2` (metadata engine) |
| Default | `v2` |
| Seed marker | `settings_engine_seeded_v2` in `appMeta` |
| Settings table | `settingsValues`, schema version 2 (`MigrationV2`) |
| Categories | 11, in `SettingsCategory` |
| Widget kinds | `toggle`, `enumPick`, `subPage`, `custom` |
| Entry points | Settings › Advanced › engine selector; the settings surface itself |
| Rule check | `scripts/check-meta-settings-rules.ps1` |

## Reading order

1. `spec.md` — what the engine and the switch must do.
2. `rules.md` — the case register; every row names its evidence.
3. `design.md` — how the gate, the store, the seed and the catalog fit.
4. `decisions/` — why the gate is hidden, why the seed is resumable and why a
   switch replays events.
5. `testing.md` — gates, fixtures and the manual checks.

## Code map

| Layer | Path |
| --- | --- |
| Catalog | `lib/features/meta_settings/data/catalog.dart`, `catalog_validation.dart` |
| Def model | `lib/features/meta_settings/model/setting_def.dart`, `model/enum/` |
| Stores | `lib/features/meta_settings/store/` |
| Engine | `lib/features/meta_settings/engine/` |
| Switch | `lib/features/meta_settings/settings_engine_controller.dart` |
| Surface | `lib/features/meta_settings/view/` |
| Table and DAO | `lib/features/meta_settings/db/` |
| Migration | `lib/features/meta_settings/db/settings_values_table.dart` (schema v2) |
| Tests | `test/features/meta_settings/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
