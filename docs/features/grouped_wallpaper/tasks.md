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
- [ ] **Previous-wallpaper flash** (`SWITCH-1`, R7). Capture the device log for a
      few home transitions, record the mechanism in `recurrences.md`, and decide
      whether an engine-warmth mitigation is worth it (`decisions/0002`).
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
