# Batch processing — tasks

Open work, linked to the requirement and rule it serves. A task that changes
behaviour also updates `rules.md`; a task that changes a judgement adds a
`decisions/` record.

## Open

- [ ] **Widget fixtures** for the share explainer (`SHR-20`), the share snackbar
      and album link (`SHR-19`) and the retention radio group (`SHR-15`,
      `SHR-16`).
- [ ] **Supersede failure fixture** (`REP-2`). A failing rename or delete must
      leave both files; today the row is unfalsified.
- [ ] **Parked-file cleanup fixture** (`HOU-2`) and **fresh-result prune
      fixture** (`HOU-3`). Both need a storage or platform fake.
- [ ] **Record-failure fixture** (`REC-6`). A recorder that throws must not fail
      the run.
- [ ] **Widget fixtures** for the banner scope (`CLS-5`), the missing delete
      action (`UI-1`), "not now" (`UI-2`) and the profile join (`PRF-5`).
- [ ] **Native executor fixtures** (`RUN-4`, `RUN-5`). The cancellation and
      per-item failure rules are native; a host test would need an Android
      instrumentation harness. Accepted gap until one exists.

## Done

- [x] Engine: tool registry, pipeline, executor, bake runner, channels
      (`0bd4476aa`).
- [x] Results: schema v17, recording, supersede, replace, move back, banner,
      results page, profiles, settings (`3c827fe54`).
- [x] Controller fixtures for the selection filter and the record trigger
      (`RUN-2`, `REC-1`, `REC-2`).
- [x] Rule register check script and the docs set.
- [x] Copy & share: share paths, run kind, share profiles, retention, entry
      points, one-time explainer and settings page (`FR-20` … `FR-24`).

## Accepted gaps

- The native executor has no host test; `RUN-4`, `RUN-5` and `APP-3` are `M` or
  `-:` in the register.
- `status` keeps `applied` and `discarded` for a future tombstone, but v1 never
  writes them (`design.md` §11).
- The banner's "not now" is not persisted; the rows stay pending, which is the
  part that matters.
- Retention only sees share copies the scanner already imported. A copy written
  seconds ago has no row yet and is picked up by the next prune.
- Copy & share has no results page and no pin: the share album is the surface,
  and the snackbar links to it (`0013`).
