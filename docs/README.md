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

`scripts/check-feature-rules.ps1 -Feature <name>` resolves every `F:` token and
every `decisions/` link in one register. The per-feature wrappers keep the older
invocation shape: `check-batch-rules.ps1`, `check-grouped-wallpaper-rules.ps1`,
`check-nav-drawer-rules.ps1`, `check-media-ops-rules.ps1`,
`check-album-contents-rules.ps1`, `check-refra-edit-rules.ps1`,
`check-meta-settings-rules.ps1`, `check-visible-range-rules.ps1`,
`check-collection-paging-rules.ps1`, `check-wallpaper-rules.ps1`,
`check-drift-db-rules.ps1`, `check-browse-only-rules.ps1`,
`check-search-filters-rules.ps1`, `check-session-restore-rules.ps1`,
`check-selection-xor-rules.ps1`, `check-stacking-rules.ps1`,
`check-known-issues-rules.ps1`, `check-logging-rules.ps1`. Run the matching one
after editing a register.
Tokens are backticked, and the checker reads the backticked segments, so a test
name may itself contain `;`.

`scripts/check-feature-docs.ps1` audits this file against the tree: every slice
has a row, a documented slice keeps `README.md`, `spec.md`, `rules.md` and at
least one decision, an exemption names its reason, and every documented register
has a wrapper listed below. `-All` resolves every register; `-Range a..b` only
the features the range touched. `.githooks/pre-push` runs it through
`scripts/run-feature-doc-gate.sh`, because CI has no dev-branch trigger.

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

Every slice under `lib/features/` is listed. A slice with its own directory is
maintained with the code; a slice without one names the reason and the feature
that owns its behaviour, so the gap stays visible instead of being omitted.

| Slice | Status | Documentation |
| --- | --- | --- |
| `album_contents_transfer` | in progress | [`album_contents_transfer/`](features/album_contents_transfer/README.md) |
| `batch_ops` | in progress | [`batch-processing/`](features/batch-processing/README.md) |
| `collection_paging` | in progress | [`collection_paging/`](features/collection_paging/README.md) |
| `grouped_wallpaper` | in progress | [`grouped_wallpaper/`](features/grouped_wallpaper/README.md) |
| `media_ops` | in progress | [`media_ops/`](features/media_ops/README.md) |
| `meta_settings` | in progress | [`meta_settings/`](features/meta_settings/README.md) |
| `nav_drawer` | in progress | [`nav_drawer/`](features/nav_drawer/README.md) |
| `refra_edit` | in progress | [`refra_edit/`](features/refra_edit/README.md) |
| `visible_range` | in progress | [`visible_range/`](features/visible_range/README.md) |
| `browse_only` | in progress | [`browse_only/`](features/browse_only/README.md) |
| `drift_db` | in progress | [`drift_db/`](features/drift_db/README.md) |
| `known_issues` | in progress | [`known_issues/`](features/known_issues/README.md) |
| `live_wallpaper_refill` | in progress | [`wallpaper/`](features/wallpaper/README.md) |
| `logging` | in progress | [`logging/`](features/logging/README.md) |
| `muzei_wallpaper` | in progress | [`wallpaper/`](features/wallpaper/README.md) |
| `search_filters` | in progress | [`search_filters/`](features/search_filters/README.md) |
| `selection_xor` | in progress | [`selection_xor/`](features/selection_xor/README.md) |
| `session_restore` | in progress | [`session_restore/`](features/session_restore/README.md) |
| `stacking` | in progress | [`stacking/`](features/stacking/README.md) |
| `wallpaper_auto_advance` | in progress | [`wallpaper/`](features/wallpaper/README.md) |
| `wallpaper_lock` | in progress | [`wallpaper/`](features/wallpaper/README.md) |

Every slice under `lib/features/` now has a documented register; a slice without a
directory would have to name its reason here, and `scripts/check-feature-docs.ps1`
fails when the reason is missing.
