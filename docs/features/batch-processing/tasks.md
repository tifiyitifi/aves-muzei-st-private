# Batch processing — tasks

Open work, linked to the requirement and rule it serves. A task that changes
behaviour also updates `rules.md`; a task that changes a judgement adds a
`decisions/` record.

## Open

- [ ] **Native executor fixtures** (`RUN-4`, `RUN-5`). The cancellation and
      per-item failure rules are native; a host test would need an Android
      instrumentation harness. Accepted gap until one exists.
- [ ] **Device checklist.** The manual steps in `testing.md` (share explainer,
      share album, profile isolation, retention, cancellation) still need a run
      on a device; they are `M` in the register where no fixture can reach them.

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
- [x] Failure-path fixtures: supersede failure (`REP-2`), parked cleanup
      (`HOU-2`), fresh result (`HOU-3`), recorder failure (`REC-6`) in
      `batch_results_service_test.dart` and `batch_run_controller_test.dart`.
- [x] View fixtures: banner scope (`CLS-5`), no delete (`UI-1`), not now
      (`UI-2`), profile join (`PRF-5`), share explainer (`SHR-20`), share
      snackbar (`SHR-19`), retention group (`SHR-15`, `SHR-16`) and the share
      profile list (`SHR-17`) under `test/features/batch_ops/view/`.
- [x] Batch views import the app's Material library, so their dialogs, sheet and
      snackbars use the app theme and messenger (`C13`).

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
