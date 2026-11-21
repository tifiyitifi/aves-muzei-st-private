# Feature documentation

Tracked documentation for the fork's own features. One directory per feature
under `docs/features/<feature>/`. Upstream-owned code has no counterpart here.

## Why this exists

The fork adds behaviour upstream does not have. A behaviour that lives only in
code gets re-decided by the next change: a fix lands in one place and silently
breaks another reader of the same input. This directory is the register that
makes the next change say what it touches before it lands.

The shape is spec-driven (spec → design → tasks), the coverage is test-driven
(every rule names the test that turns it red), and the acceptance criteria are
written as behaviour (one observable behaviour per sentence). No Gherkin runner
is added: Flutter's `test()`/`group()` stays the executor, and the rule register
is the link between a sentence and a test.

`AGENTS.md` is the project constitution: toolchain, layering, flavours,
persistence and privacy. It is not duplicated here.

## Layout

```
docs/features/<feature>/
  README.md        status, scope, versions, reading order
  spec.md          requirements and acceptance criteria (EARS)
  design.md        how it works: pipeline, data model, invariants, anti-patterns
  rules.md         one row per case the feature must get right, with coverage
  recurrences.md   R: complaints that return; C: couplings that spread a change
  testing.md       gates, fixtures, manual checks, commit discipline
  tasks.md         open work, linked to requirements
  contracts/       cross-language or cross-store contracts
  decisions/       append-only decision records (ADR)
```

Not every feature needs every file on day one. A feature with no open work has a
short `tasks.md`; a feature with no cross-language seam has no `contracts/`.
What a shipped feature must have is `spec.md`, `rules.md` and `decisions/`.

## Status vocabulary

- **shipped** — on a release branch.
- **in progress** — implemented on a dev branch, not released.
- **planned** — specified, not implemented.

## Writing rules

- One behaviour per sentence; no "and also".
- Acceptance criteria use EARS: `WHEN <trigger>, THE SYSTEM SHALL <response>`.
  Prefer a condition and a response over a description of the UI.
- A rule that stops being true is **superseded**, not deleted: keep the row and
  point at the row or decision that replaced it.
- A decision record is append-only; a reversed decision keeps its text and gains
  a `Superseded by` line.
- Cite commits as a short SHA. A claim that cannot cite one is either a task
  (`tasks.md`) or not a claim.
- Code paths are repo-relative (`lib/features/batch_ops/...`), never absolute.

## Coverage tokens

`rules.md` uses `;`-separated tokens in its coverage column:

- `F:<test file stem>#<test name>` — a test with exactly that name exists in
  `test/**/<stem>.dart` and fails when the rule breaks.
- `M` — needs a human on a device; the step is listed in `testing.md`.
- `-:<reason>` — deliberately unfalsified, with the reason it cannot be tested
  on the host.

`scripts/check-batch-rules.ps1` resolves every `F:` token and every
`decisions/` link in the batch register. Run it after editing a register.

## Privacy

This repository may be published; the machine it is built on is not.

- Use stand-in paths (`/storage/emulated/0/DCIM/Camera`, `Pictures/...`,
  `C:\work\library`) and stand-in names (`IMG_0001.jpg`, `book-a`).
- Never write a real local path, photo title, album name, account name or
  machine name into a doc.
- Manual verification notes say "a photo from the camera album", never the file.
- `scripts/check-local-paths.ps1` runs on commit; run it with `-All` after
  editing docs.

## Features

| Feature | Status | Directory |
| --- | --- | --- |
| Batch processing | in progress | [`batch-processing/`](features/batch-processing/README.md) |
| Grouped wallpaper | in progress | [`grouped_wallpaper/`](features/grouped_wallpaper/README.md) |
