# Grouped wallpaper — specification

What the feature must do. Mechanism lives in `design.md` and in the slice
README; the case register in `rules.md` maps every requirement to the test that
holds it.

## Glossary

| Term | Meaning |
| --- | --- |
| **Group** | A saved visible range plus its per-surface effects and framing. |
| **Slot** | One baked photo the renderer can upload. Slots are the queue. |
| **Queue** | `previous → current → next`, both neighbours baked. |
| **Generation** | A counter Dart bumps on every `state.json` write. |
| **Renderer** | The native live wallpaper engine that uploads and draws slots. |
| **Displayed slot** | The slot the renderer is really drawing, which can differ from `state.json`'s `current` after a promotion. |
| **Promotion** | A step that shows a queued neighbour without a bake. |
| **Surface** | Home or lock; a split group draws a separate decoy on the lock. |

## Requirements

Each requirement is one observable behaviour. The acceptance criterion is
written as `WHEN <trigger>, THE SYSTEM SHALL <response>`; the `Rules:` line
names the register rows that hold it.

### FR-1 — The app describes the frame the renderer draws

WHEN the view page describes a home photo, THE SYSTEM SHALL describe the slot
the renderer is drawing and SHALL NOT describe the baked `current` when the
renderer has promoted another slot.

Rules: `DISP-1`, `DISP-2`, `DISP-3`.

### FR-2 — A slot id is only meaningful inside its generation

WHEN the renderer's state and the on-disk `state.json` are not the same
generation, THE SYSTEM SHALL use the renderer's own slot metadata instead of
resolving the slot id against the newer file.

Rules: `DISP-4`.

### FR-3 — A step is reflected immediately and repeatedly

WHEN the user steps the photo, THE SYSTEM SHALL describe the new photo after
every step, including consecutive steps taken before the background refill has
written the next generation.

Rules: `DISP-2`, `DISP-3`.

### FR-4 — A tap has exactly one effect

WHEN a tap can promote a queued slot, THE SYSTEM SHALL promote it and SHALL NOT
also start a bake; WHEN it cannot promote yet, THE SYSTEM SHALL buffer the tap
and replay it once the slot is uploaded, unless the wallpaper must not move at
all.

Rules: `PROM-1`, `PROM-2`, `PROM-3`.

### FR-5 — A reload never blanks or rewinds the wallpaper

WHEN a reload runs, THE SYSTEM SHALL keep the frame on screen and the uploaded
neighbours until a newer state or a deliberate step replaces them.

Rules: `RET-1`, `RET-2`, `RET-3`.

### FR-6 — A bake matches the pixels the user sees

WHEN the engine bakes a frame, THE SYSTEM SHALL size it from the real renderer
surface, not from a launcher hint that can be square.

Rules: `SIZE-1`, `SIZE-2`.

### FR-7 — A lost wallpaper is offered back, never silently taken

WHEN an OEM resets or replaces the wallpaper, THE SYSTEM SHALL offer the user a
one-tap way back and SHALL NOT rebind silently.

Rules: `RSTR-1`, `RSTR-2`.

### FR-8 — The system transitions to and from this wallpaper

WHEN the system rebinds the live wallpaper after its engine was destroyed, the
system may draw the wallpaper it kept as the previous one until the new engine
draws its first frame. This is outside the app; the feature documents it and
may only reduce how often the engine is killed.

Rules: `SWITCH-1`.

### FR-9 — A gesture-opened view is the root of its flow

WHEN a wallpaper gesture or a notification opens the view, THE SYSTEM SHALL make
it the app's root route, so backing out leaves to the desktop through the
double-back setting; 「Open wallpaper groups」 SHALL push the playing group's page
over it, and backing out of that page SHALL land on the view again. A view opened
from the group page SHALL keep that page below it and pop back to it.

Rules: `NAV-1`, `NAV-2`.

### FR-10 — The view hands the photo to the gallery

WHEN the user opens the photo from the view, THE SYSTEM SHALL offer the viewer,
the photo's own album and the group's whole media set. The album destination
SHALL be the stored album the photo belongs to, never a path condition, and both
gallery destinations SHALL reveal the photo in the list instead of starting at
its top.

Rules: `DEST-1`, `DEST-2`, `DEST-3`.

### FR-11 — The drawer opens the wallpaper page the range opens

WHEN the user opens the wallpaper groups from the drawer, THE SYSTEM SHALL open
the same destination as the visible range's「Open wallpaper groups」action: the
page itself in a separate navigation mode, and the single range entry on the
wallpaper page in the shared mode.

Rules: `NAV-3`.

### FR-12 — The new-photo marker is seeded when a surface starts

WHEN a group (or its split lock range) starts playing or moves to a different
range, THE SYSTEM SHALL seed the new-photo marker from that source's id
high-water before the first pick, so "new" means added after setup rather than
not yet shown. WHEN the same group starts its walk over, THE SYSTEM SHALL keep
the marker it already has.

Rules: `ORD-1`, `ORD-2`, `ORD-3`, `ORD-4`, `ORD-5`.
