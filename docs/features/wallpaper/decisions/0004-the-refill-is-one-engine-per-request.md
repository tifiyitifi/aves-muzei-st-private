# 0004 — The refill is one engine per request

Status: accepted.

## Context

A wallpaper tap or an interval can change the wallpaper while neither the page
nor the app process is alive. Keeping a Flutter engine alive would cost memory,
be killed by the system anyway, and still need a wake-up path.

The bake must stay in Dart: sources, EXIF decoding and both effect pipelines
already live there, and a second Kotlin implementation would drift from the
preview.

## Decision

The native worker starts a short-lived Flutter engine, the isolate initializes
platform services, settings, vaults and the lock service, registers one method
channel, reports `initialized`, runs one refill for the requested target, and is
destroyed. Targets are `muzei` and `grouped`; the map in
`lib/features/live_wallpaper_refill/refill_entry.dart` is the only place that
knows both.

The callback handle is registered at every app start because it is part of the
AOT snapshot and changes with each build. A host without the background pipeline
(desktop, tests) logs and skips.

## Consequences

- A tap after a force-stop still uses the prefetched slot; a normal process death
  is covered.
- The run is a plain WorkManager job, deliberately not expedited: on Android 12+
  an expedited job becomes a foreground service for a two-second bake.
- The isolate has its own logging state, so it opens the feature channels itself.
- The worker may invoke only after `initialized`, so a half-started isolate never
  serves a refill.
