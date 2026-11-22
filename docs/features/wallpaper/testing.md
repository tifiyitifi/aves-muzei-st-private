# Wallpaper family — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Dart tests | `.flutter/bin/flutter.bat test test/features/muzei_wallpaper test/features/wallpaper_auto_advance test/features/wallpaper_lock` | do the state, bake, source, interval and lock rules hold |
| Kotlin unit tests | `./gradlew :app:testCustomDebugUnitTest "-Ptarget=lib/main_custom.dart"` | do the native state, queue, viewport and interval decisions still hold |
| Rule register | `pwsh -NoProfile -File scripts/check-wallpaper-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it work on a real launcher |

The Kotlin tests the family relies on are `AdvanceRequestQueueTest`,
`WallpaperFileStateTest`, `WallpaperViewportTest` (Muzei) and
`AutoAdvanceIntervalTest` (refill). The register records them as `-:native`
because the host register checker only resolves Dart test names.

## Fixtures

- State, bake, source, prefs and interval tests are host tests; the state store
  uses a temporary directory and the app's in-memory services.
- The refill isolate has no host fixture: it needs the native worker and a real
  Flutter engine. Its contract (`initialized` before `refill`, target dispatch)
  is verified on a device by the checklist.
- `wallpaper_lock_service_test` injects the security service and the store, so
  the PIN rules run against fakes.

## Device checklist

1. Set the Muzei wallpaper, then tap twice quickly. Expect both taps to advance
   instantly and the page to describe the photo actually shown. (`CTL-2`,
   `CTL-10`)
2. Force-stop the app, then tap the wallpaper. Expect the background refill to
   advance and the next launch to adopt it. (`REF-1`, `REF-3`)
3. Change the effects while dragging, then release. Expect the preview to follow
   the slider and the desktop to rebake once. (`APL-1`, `CTL-9`)
4. Pick a single picture, delete the original from the library, restart. Expect
   the wallpaper to keep showing the private copy. (`SRC-13`)
5. Open the interval editor, add a custom value at the bounds, delete it, then
   reset all. Expect both wallpapers' selections to follow and `Off` to remain.
   (`AUT-1`, `AUT-5`)
6. Lock the group switch with a PIN, restart the app, then try to leave the
   group. Expect the PIN prompt and the group to stay on a wrong PIN. (`LCK-4`,
   `LCK-6`)
7. Leave the grouped wallpaper while a video plays for longer than its interval.
   Expect no bakes, and one advance when the home screen returns. (`AUT-9`)

## Privacy

Describe photos and albums by kind. Never record a real wallpaper path, a PIN or
a device account in a test or this file.
