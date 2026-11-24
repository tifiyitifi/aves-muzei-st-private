# Grouped wallpaper — tasks

Open work, linked to the requirement and rule it serves. A task that changes
behaviour also updates `rules.md`; a task that changes a judgement adds a
`decisions/` record.

## Open

- [x] **Register for the feature** (`README.md`, `spec.md`, `design.md`,
      `rules.md`, `recurrences.md`, `testing.md`, `tasks.md`, `decisions/`).
- [x] **Display drift on consecutive steps** (`DISP-3`, `DISP-4`, R1b). The
      `displayedSlot` channel now carries the renderer's generation and the drawn
      slot's metadata; the view page resolves the frame from that snapshot and
      never maps the id across generations.
- [x] **A step that baked reads the baked frame** (`DISP-8`, `DISP-9`, R1c). The
      view page reads `readBakedFrame` after a bake, and `readDisplayedFrame`
      falls back to the baked current when the drawn slot's file is gone
      (`decisions/0004`).
- [x] **Previous-wallpaper flash** (`SWITCH-1`, R7/R7b). Device capture shows
      the launcher's cached transition frame, not the renderer: the flashed
      photo is absent from the texture map and the frame cache, and a chooser
      set (`SET_LIVE`) removes the flash while a silent rebind
      (`PACKAGE_UPDATE_FINISHED`) brings it back (`decisions/0005`).
- [ ] **One-tap re-apply after a package replace** (`SWITCH-1`, R7b). When the
      wallpaper is still ours but the package replace rebound it silently, offer
      a notification/in-app notice that opens the live wallpaper chooser once
      per version. The app cannot bind the component itself
      (`SET_WALLPAPER_COMPONENT` is not granted).
- [ ] **Device checklist** (`testing.md` §5) for `SWITCH-1`, R5, R3 and R2.
- [ ] **Migrate the slice README** (`lib/features/grouped_wallpaper/README.md`)
      into `design.md` once the register is stable; keep one home per sentence
      (`decisions/0003`).

## Done

- [x] The rule register, the recurrences and the decisions set.
- [x] The checker script and the docs registration.
- [x] The display slice: the renderer snapshot and its generation.

## Accepted gaps

- The native GL renderer has no host test; `SWITCH-1` is `M`, and several native
  rows are held by the pure Kotlin decision classes instead.
- The full mechanism narrative still lives in the slice README until the
  migration lands.
- `newPhotoMarker()` reads the allocator's high-water with `nextId - 1`, which
  consumes one id per read. The gap is never reused but is harmless: reads are
  per user action, not per photo (`decisions/0010`).
