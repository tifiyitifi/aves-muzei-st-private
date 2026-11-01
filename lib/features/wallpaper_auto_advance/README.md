# Wallpaper auto-advance interval options

The **option list** for wallpaper auto-advance is global; the **selected value**
is not. Every grouped wallpaper group stores its own interval in
`wallpaper_groups.interval` (seconds), and the Muzei wallpaper stores its own in
`SharedPreferences` (`muzei_wallpaper.auto.interval_seconds`). This slice owns
only the shared list and the management actions on it.

## Data flow

```
assets/wallpaper_intervals.json     (shipped defaults + reset target)
        │  data/default_intervals.dart
        ▼
WallpaperIntervalDefaults ──first run / recovery──► AppMeta
        │                              wallpaper.autoAdvanceIntervals
        │                              {"defaults":[...],"customs":[...]}
        ▼
WallpaperIntervalCatalog  (defaultInterval, shippedDefaults, defaults, customs)
        │
        ├── grouped page  ──► one interval per group
        └── Muzei page    ──► one interval for the Muzei wallpaper
```

- `WallpaperAdvanceInterval` is a value object in seconds. `0` is off; user
  values are clamped to `3 s .. 30 days`. Stored values are preserved as-is (a
  custom interval is data, not a code-defined enum member), but corrupt entries
  are skipped rather than turned into off.
- `assets/wallpaper_intervals.json` is the only source of the shipped list and
  of `defaultSeconds` (currently `0`, off). It ships `[0, 900, 1800, 3600,
  10800, 21600, 86400, 259200]`.
- The AppMeta document keeps `defaults` and `customs` apart so Reset can clear
  both and 「Add default intervals」 can restore only the built-ins. A missing or
  unreadable document seeds the shipped list; an intentional
  `{"defaults":[],"customs":[]}` is never re-seeded.

## Actions

| Action | Option list | Selections |
|---|---|---|
| Long-press → delete selected customs | remove those `customs` | only groups/Muzei using a removed value → reset target |
| **Clear all intervals** | `defaults = []`, `customs = []` | unchanged (the current value keeps showing as a synthetic option) |
| **Reset all to default** | `defaults = shippedDefaults`, `customs = []` | every group and Muzei → reset target (off) |
| **Add default intervals** | add the missing `shippedDefaults` | unchanged |
| Add a custom interval | new value → `customs`; a missing shipped value → `defaults` | caller selects the returned option |

- After Clear all the list can be empty. `WallpaperIntervalOptionList` still
  shows the caller's current value as a synthetic, non-deletable entry, so the
  radio group always has a valid selection.
- Deleting a custom option resets only selections that used it. Reset all to
  default is the only action that resets everything; Clear all only edits the
  list.
- `WallpaperIntervalSelectionReset` is the seam to both wallpapers:
  `WallpaperGroupController.resetIntervals` writes the group rows without
  bumping `updatedAt` (no re-bake), `wallpaperPrefs.setInterval` persists the
  Muzei value, and `wallpaperEngineLink.refreshSchedule` /
  `WallpaperBridge.scheduleAutoAdvance` re-arm the schedules. The actions are
  rare and idempotent, so a failure is logged and the user can repeat them.

## UI

Both `GroupedWallpaperAutoAdvancePage` and
`MuzeiWallpaperAutoAdvancePage` embed `WallpaperIntervalOptionList` and mount
`WallpaperIntervalMoreButton` in the app bar. Normal mode is a radio list plus an
「Add interval」 entry; the overflow menu holds Add default / Clear all / Reset all
to default / About. A long press on a custom option enters multi-select mode;
built-ins are shown disabled with a 「Built-in」 label and a SnackBar explains that
they cannot be deleted individually.

`WallpaperIntervalAddSheet` edits four boxes — days, hours, minutes, seconds —
each digits-only and capped at 1000, with a live total. It starts from the
current interval, or from 10 minutes when the interval is off, and validates
`3 s .. 30 days`. Mobile opens it as a scroll-controlled bottom sheet, wider
layouts as a centered dialog.

Performance follows the IRIS keyboard-form pattern: the form is built once and
cached, the shell never reads `MediaQuery.viewInsetsOf`, and the only reader is a
private `AnimatedPadding` leaf, so IME animation frames repad instead of
rebuilding the fields. Mobile also skips `autofocus`, so the IME cannot fight the
sheet's entrance animation.

All prose explanations live in `WallpaperIntervalAboutPage` (reached from the
overflow menu), so the picker and the editor stay free of hint paragraphs.

No new row is added to Settings → Visible & wallpaper: the management entry
point is where the interval is chosen.

## Files

- `model/wallpaper_advance_interval.dart` — value object and bounds.
- `model/wallpaper_interval_parts.dart` — the editor's days/hours/minutes/seconds
  boxes, decomposition and validation.
- `model/wallpaper_interval_catalog.dart` — option list, `missingDefaults`,
  ordering/dedup helpers.
- `data/default_intervals.dart` — tolerant JSON parser and cached asset loader.
- `db/wallpaper_interval_options_store.dart` — AppMeta persistence and seeding.
- `services/wallpaper_interval_options_controller.dart` — `ChangeNotifier`
  singleton and the add/delete/clear/reset actions.
- `services/wallpaper_interval_selection_reset.dart` — fan-out to grouped and
  Muzei selections and schedules.
- `view/wallpaper_interval_label.dart` — seconds → 「Every N minutes/hours/days」.
- `view/wallpaper_interval_about_page.dart` — the shared explanation page.
- `view/widgets/` — the shared option list, the overflow menu and the add sheet.

Tests mirror these paths under `test/features/wallpaper_auto_advance/`; the group
row reset is covered in `wallpaper_group_controller_test.dart` and the Muzei
custom-seconds round-trip in `wallpaper_prefs_test.dart`.
