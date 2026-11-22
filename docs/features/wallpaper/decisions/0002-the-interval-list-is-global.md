# 0002 — The interval list is global

Status: accepted.

## Context

Two wallpapers offer the same auto-advance picker. The values a user can choose
are the same set, but the selected interval belongs to one group or to the Muzei
wallpaper, not to the app.

Copying the option list into each wallpaper would make the two drift: adding a
default in one build would not appear in the other, and resetting one would not
mean the same thing.

## Decision

`wallpaper_auto_advance` owns the option catalog: the shipped default list, the
custom values, the editor and the management actions. The catalog lives in one
`appMeta` document (`defaults` and `customs` kept apart). Each wallpaper stores
only its selected seconds: a `wallpaper_groups` column for a group, a
`SharedPreferences` value for Muzei.

Deleting an option resets only the selections that used it, through one reset
seam that writes the group rows without bumping `updatedAt` (so no rebake) and
re-arms both schedules. `Off` is pinned as the off switch and the reset target.

## Consequences

- Adding a shipped option is one asset change plus a list-version bump.
- The editor and its actions are shared; neither wallpaper page owns a private
  copy.
- Clearing the list cannot remove `Off`, or there would be no way to switch
  auto-advance off again.
- A failed fan-out is logged; the actions are rare and idempotent.
