# Wallpaper family — design

## Two wallpapers, one mechanism vocabulary

| | Muzei | Grouped |
| --- | --- | --- |
| State root | `filesDir/muzei_wallpaper` | `filesDir/grouped_wallpaper` |
| Dart state | `state.json` (v1) | `state.json` (v7) |
| Native runtime | `runtime.json` | `runtime.json` |
| Bakes | sharp + 2 effect PNGs per artwork | per-slot PNGs, per group |
| Interval | one `SharedPreferences` value | one `wallpaper_groups` column |
| Lock | none of its own | group switch lock (shared service) |

They share the vocabulary — slot, generation, promotion, runtime adoption, spare
depth — but not the files. A change to one must be checked against the other;
that is what `recurrences.md` C1/C2 are for.

## The state files are the contract

Dart writes `state.json` (slots, current/next/next2, recent, effects, gestures,
ordering, generation). The native renderer writes only `runtime.json` (which slot
it actually promoted) and consumes the slot PNGs. Both sides read the generation:

- a slot id is meaningful only with the generation that produced it;
- a `runtime.json` with a matching generation wins, because the renderer may have
  promoted a slot on its own;
- a mismatched generation means the runtime is stale and the baked state is the
  answer.

Writes go through `WallpaperStateStore.runExclusive`, which holds a file lock, so
the foreground page and a background refill cannot interleave. Writes are atomic:
temp file, then rename.

## A tap is a promotion, not a bake

A tap on the live wallpaper is a texture swap in the renderer. Dart keeps a spare
slot (`next`, optionally `next2`), so the renderer can promote without Flutter
being alive. The renderer records the promoted slot in `runtime.json`; the next
Dart adoption reads it and bakes the missing spare.

Baking is hundreds of milliseconds, so a tap that arrives during one must not be
rewound by the commit: the commit only writes the spare slot, never `current`, if
an advance happened meanwhile. A prefetch that loses the race still fills the
queue.

When no app engine is attached, the tap cannot be served by the renderer alone;
the native worker starts the shared headless refill.

## The background refill is one short engine per run

`live_wallpaper_refill` is not a long-lived service. The worker starts a Flutter
engine, the isolate initializes platform services, settings, vaults and the lock
service, registers one channel handler, reports `initialized`, runs one refill,
and is destroyed. This keeps taps working after the app is closed or killed
without keeping a process alive.

The callback handle is registered at every app start because it is part of the
AOT snapshot and changes with each build. If the callback cannot be registered
(desktop, tests), the feature logs and skips: there is no background pipeline
there.

## The interval list is global; the selection is not

`assets/wallpaper_intervals.json` is the only source of the shipped list and the
reset target (off). `appMeta` stores `defaults` and `customs` separately so that
"Add default intervals" can restore built-ins while "Reset all" can clear both.
A missing or unreadable document is re-seeded; an intentional empty document is
not.

The selected value lives with its owner: `wallpaper_groups.interval` for a group,
`muzei_wallpaper.auto.interval_seconds` for Muzei. A deletion resets only the
selections that used the deleted value; the fan-out seam
(`WallpaperIntervalSelectionReset`) writes the group rows in a way that does not
bump `updatedAt` (no rebake) and re-arms both schedules.

For the grouped wallpaper, a due advance is deferred while its surface is not
visible: the worker records a pending flag, re-arms, and returns. The interval is
wall-clock time, applied at the next observable moment. Muzei keeps its own
policy.

## Locks are casual, independent and per kind

- **Visible range lock** is a column on the range row; the service only verifies
  the PIN to unlock or temporarily ignore a locked range.
- **Group switch lock** is a flag plus the group id, persisted in `appMeta`, so it
  survives leaving the page, the app and a process restart.

Each kind owns a 4-digit PIN in the encrypted preferences (the vault store),
defaulting to `1234`. The PINs are never part of settings import/export, and there
is no "forgot PIN" flow: clearing app data is the reset. This is not a security
boundary and the UI says so.

## Anti-patterns

- **Reading `state.current` without the generation.** It is the recurring display
  bug (`grouped_wallpaper` R1).
- **Writing `current` from a bake that raced a tap.** The user's tap is rewound.
- **Adding an option to the asset without bumping the list version.** Existing
  installs keep the old catalog.
- **Storing the interval list inside either wallpaper's state.** It is shared;
  two copies drift.
- **Treating the PIN as security.** It only stops a casual tap.
- **Keeping the refill engine alive.** A long-lived isolate costs memory and is
  killed by the system anyway; one run per request is the contract.
