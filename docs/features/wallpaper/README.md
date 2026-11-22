# Wallpaper family

The two live wallpapers and the services they share: the Muzei port, the
grouped (per-range) wallpaper's shared scheduling and lock pieces, and the
headless refill that lets a tap or an interval change the wallpaper while the app
is not running.

The two wallpapers keep their own state files, renderers, pages and intervals.
This directory is the register for what they share; the grouped wallpaper's own
pipeline is documented in `docs/features/grouped_wallpaper/`, and the Muzei
mechanics in `lib/features/muzei_wallpaper/README.md`.

Status: **in progress**. Both wallpapers and the shared slices are on
`avest-dev`; nothing is released yet.

## Scope

In scope:

- baking an artwork into the slot PNGs the renderer draws (Muzei);
- the Dart/native state contract (`state.json`, `runtime.json`, slots);
- a tap that promotes a queued slot instead of baking;
- source selection, ordering, single-artwork copies and the viewer policy;
- the shared auto-advance interval catalog, its editor and its fan-out to both
  wallpapers;
- the PIN-protected wallpaper locks;
- the headless refill entrypoint and its worker channel.

Out of scope:

- the grouped wallpaper's group state, renderer and view (see
  `grouped_wallpaper/`);
- Muzei's original GL renderer internals, ported as-is (see the slice README);
- a real security boundary: both locks are casual protection inside Aves.

## Version facts

| Fact | Value |
| --- | --- |
| Muzei state root | `filesDir/muzei_wallpaper` |
| Muzei state file | `state.json` (schema `currentVersion = 1`), native `runtime.json` |
| Slots | `slots/<id>/sharp.png`, `effects_home.png`, `effects_lock.png`, `art.json` |
| Grouped state root | `filesDir/grouped_wallpaper` (schema 7, see its doc) |
| Refill channel | `deckers.thibault/aves/live_wallpaper_refill` |
| Refill targets | `muzei`, `grouped` |
| Interval store | `appMeta` key `wallpaper.autoAdvanceIntervals` |
| Interval bounds | 3 s .. 30 days; `0` is off |
| Default interval | `0` (off) |
| Lock PINs | 4 digits, encrypted preferences, default `1234` per kind |
| Lock kinds | `visibleRange`, `groupSwitch` |
| Rule check | `scripts/check-wallpaper-rules.ps1` |

## Reading order

1. `spec.md` — what the family must do.
2. `rules.md` — the shared case register; every row names its evidence.
3. `design.md` — the state contract, the tap path and the background worker.
4. `lib/features/muzei_wallpaper/README.md` and
   `lib/features/wallpaper_auto_advance/README.md` — the mechanism narratives.
5. `decisions/` — why a tap never bakes, why the interval list is global, why
   the locks are separate.
6. `testing.md` — gates, fixtures and the device checks.

## Code map

| Layer | Path |
| --- | --- |
| Muzei model and state | `lib/features/muzei_wallpaper/model/` |
| Muzei services | `lib/features/muzei_wallpaper/services/` |
| Muzei views | `lib/features/muzei_wallpaper/view/` |
| Muzei entrypoints | `lib/features/muzei_wallpaper/entry/` |
| Shared intervals | `lib/features/wallpaper_auto_advance/` |
| Locks | `lib/features/wallpaper_lock/` |
| Headless refill | `lib/features/live_wallpaper_refill/` |
| Native Muzei | `android/app/src/main/kotlin/deckers/thibault/aves/features/muzei_wallpaper/` |
| Native refill worker | `android/app/src/main/kotlin/deckers/thibault/aves/features/live_wallpaper_refill/` |
| Tests | `test/features/muzei_wallpaper/`, `test/features/wallpaper_auto_advance/`, `test/features/wallpaper_lock/` |
| Native tests | `android/app/src/test/kotlin/deckers/thibault/aves/features/{muzei_wallpaper,live_wallpaper_refill}/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
