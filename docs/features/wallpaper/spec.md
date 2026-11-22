# Wallpaper family — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## Baking and the state contract

- WHEN a bake runs, THE SYSTEM SHALL write the sharp image and both effect images
  at the target size, cover-cropped around the source's centre.
- WHEN the requested size exceeds the GPU texture limit, THE SYSTEM SHALL clamp it
  and keep its aspect ratio.
- WHEN an effect is the identity, THE SYSTEM SHALL reuse the sharp bytes.
- WHEN only effects change, THE SYSTEM SHALL rebake the effect images without
  decoding the artwork again.
- WHEN decoding fails, THE SYSTEM SHALL surface the failure as a bake error.
- WHEN state is written, THE SYSTEM SHALL write it atomically through the temp
  directory.
- WHEN stored JSON is corrupt or its version is unknown, THE SYSTEM SHALL read it
  as absent instead of throwing.
- WHEN a slot id or artwork is invalid or duplicated, THE SYSTEM SHALL drop the
  invalid entry.
- WHEN the state and the renderer disagree on generation, THE SYSTEM SHALL treat a
  slot id as valid only inside the generation that produced it.
- WHEN `runtime.json` matches the state generation, THE SYSTEM SHALL treat the
  renderer's slot as current.
- WHEN two processes write the state, THE SYSTEM SHALL serialise them with the
  file lock.

## Taps and promotion

- WHEN a tap can promote, THE SYSTEM SHALL promote the queued neighbour and SHALL
  NOT bake again.
- WHEN a second spare exists, THE SYSTEM SHALL keep the first two taps instant.
- WHEN a tap arrives during a bake, THE SYSTEM SHALL not let the commit rewind it.
- WHEN a prefetch races an advance, THE SYSTEM SHALL still fill the queue.
- WHEN the spare pick runs, THE SYSTEM SHALL exclude the artwork already queued.
- WHEN an older build left a duplicate spare, THE SYSTEM SHALL repair it on
  startup.
- WHEN a tap arrives while no app engine runs, THE SYSTEM SHALL enqueue a
  background refill instead of dropping it.

## Sources, ordering and single artwork

- WHEN a source is queried, THE SYSTEM SHALL return still images only and SHALL
  exclude hidden filters and locked vaults.
- WHEN the ordering is in-order, THE SYSTEM SHALL wrap the cursor at both ends.
- WHEN the ordering is random, THE SYSTEM SHALL be reproducible from a seed and
  SHALL avoid the current and recently shown artworks.
- WHEN the ordering is new-then-random, THE SYSTEM SHALL serve entries above the
  marker first, then random.
- WHEN the marker is seeded, THE SYSTEM SHALL start from the newest artwork at
  source setup, not from zero.
- WHEN the chosen artwork is a single picture, THE SYSTEM SHALL keep a private
  copy that outlives deleting the original.
- WHEN the copy and the library row both exist, THE SYSTEM SHALL prefer the
  library original in the viewer.
- WHEN the source is deleted or unconfigured, THE SYSTEM SHALL keep the baked
  wallpaper and stop producing new ones.
- WHEN a filter cannot be expressed for the paged path, THE SYSTEM SHALL report it
  as unsupported instead of picking from the wrong set.
- WHEN the user picks filters, THE SYSTEM SHALL force the image MIME restriction
  and drop video filters.

## Effects, framing and the preview

- WHEN no effect is configured, THE SYSTEM SHALL leave the artwork untouched.
- WHEN an out-of-range effect value is read, THE SYSTEM SHALL clamp it.
- WHEN effects are linked, THE SYSTEM SHALL apply the edited surface to both.
- WHEN framing is configured, THE SYSTEM SHALL store it per surface and SHALL not
  link it.
- WHEN a config predates the scroll switch, THE SYSTEM SHALL read the legacy
  value.
- WHEN the preview is shown, THE SYSTEM SHALL use the same cover and effect maths
  as the bake.

## Auto-advance intervals

- WHEN an interval is stored, THE SYSTEM SHALL keep it in 3 s .. 30 days, with `0`
  meaning off.
- WHEN a shipped option list is missing or unreadable, THE SYSTEM SHALL seed it
  once; an intentional empty list SHALL survive.
- WHEN an option is deleted, THE SYSTEM SHALL reset only the selections that used
  it; `Off` SHALL never be deleted.
- WHEN all intervals are cleared, THE SYSTEM SHALL keep `Off` as the only option.
- WHEN all intervals are reset, THE SYSTEM SHALL restore the shipped list and
  reset every selection.
- WHEN defaults are re-added, THE SYSTEM SHALL fill only the missing built-ins.
- WHEN a grouped advance is due while the wallpaper is not visible, THE SYSTEM
  SHALL defer it and re-arm instead of baking.
- WHEN the item is added through the editor, THE SYSTEM SHALL accept only a total
  within bounds and boxes capped at 1000.

## Locks

- WHEN no PIN has been written, THE SYSTEM SHALL use the default PIN.
- WHEN the group switch starts, THE SYSTEM SHALL start unlocked.
- WHEN locking, THE SYSTEM SHALL record the group without asking for a PIN.
- WHEN unlocking or changing the PIN, THE SYSTEM SHALL require the current PIN.
- WHEN a wrong PIN is entered, THE SYSTEM SHALL keep the lock.
- WHEN a PIN is stored, THE SYSTEM SHALL keep it 4 digits and store each kind
  under its own key.
- WHEN the service restarts, THE SYSTEM SHALL keep the group lock.

## Background refill

- WHEN the worker starts the refill isolate, THE SYSTEM SHALL register the channel
  handler before reporting `initialized`.
- WHEN the refill starts, THE SYSTEM SHALL initialize the platform services,
  settings, vaults and the lock service first.
- WHEN a refill targets a wallpaper, THE SYSTEM SHALL dispatch by target id.
- WHEN an unknown target or method arrives, THE SYSTEM SHALL reject it.
- WHEN `advance` is not the literal `true`, THE SYSTEM SHALL not advance the
  wallpaper.
- WHEN the app starts, THE SYSTEM SHALL register the callback handle again,
  because it changes with each build.
