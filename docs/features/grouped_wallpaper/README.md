# Grouped wallpaper

A live wallpaper that shows photos from the current group, keeps a
`previous → current → next` queue ready, and advances from a tap, the bar
notification or a view-page step.

Status: **in progress**. The feature has been iterated on `avest-dev` for many
releases; this directory is its register, added after a long run of fixes that
kept returning to the same seams.

## Scope

In scope:

- one current group, with home and lock surfaces optionally split;
- a three-slot promotion queue baked by Dart and drawn by the native renderer;
- photo steps from a wallpaper gesture, the notification bar and the view page;
- auto-advance, usage history, group switching and the effects pages;
- keeping the wallpaper alive across an OEM that resets it on update.

Out of scope:

- rendering the photo in Dart (the app bakes frames; the native service only
  uploads textures);
- reading the app database from the wallpaper service;
- pixel work beyond covering, rotating and the blur/dim/grey effects.

## Version facts

| Fact | Value |
| --- | --- |
| Native service | `GroupedLiveWallpaperService` |
| Method channel | `deckers.thibault/aves/grouped_wallpaper` |
| State root | `filesDir/grouped_wallpaper` |
| Dart state file | `state.json` (schema `currentVersion = 7`) |
| Renderer runtime file | `runtime.json` |
| Database schema | 17 (`wallpaper_groups`, `grouped_wallpaper_history`; grouped migrations v12–v14) |
| Entry point | collection action, wallpaper group page, notification |
| View route | `/grouped_wallpaper/view` |
| Group page route | `/wallpaper_groups` |

## Reading order

1. `spec.md` — what the feature must do, as acceptance criteria.
2. `rules.md` — the case register; every row names the test that holds it.
3. `recurrences.md` — the complaints that return and the couplings behind them.
   Read this before changing a rule: several fixes have already failed here.
4. `docs/features/wallpaper/` — the shared state contract, interval catalog,
   locks and headless refill this feature uses.
4. `design.md` — the two-file state model and the invariants.
5. `decisions/` — why the judgement calls went the way they did.
6. `testing.md` — the gates a change has to pass.
7. `tasks.md` — what is still open.

The full mechanism narrative is `lib/features/grouped_wallpaper/README.md`; it
stays the deep design doc until the migration tracked in `tasks.md`. This
directory owns the requirements, the case register and the recurrences.

## Code map

| Layer | Path |
| --- | --- |
| Dart models | `lib/features/grouped_wallpaper/model/` |
| Dart engine | `lib/features/grouped_wallpaper/engine/` |
| Dart services | `lib/features/grouped_wallpaper/services/` |
| Dart views | `lib/features/grouped_wallpaper/view/` |
| Native service and renderer | `android/app/src/main/kotlin/deckers/thibault/aves/features/grouped_wallpaper/` |
| Dart tests | `test/features/grouped_wallpaper/` |
| Native tests | `android/app/src/test/kotlin/deckers/thibault/aves/features/grouped_wallpaper/` |
| L10n keys | `lib/l10n/app_en.arb` (`wallpaperGroup*`) |

## Privacy note

Every path and title in this directory is a stand-in. A manual verification note
describes the kind of photo, never the file. See `docs/README.md`.
