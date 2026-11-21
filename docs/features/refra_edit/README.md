# ReFra edit

Copy-first editing: every edit session copies the source into
`Pictures/aves_refra_edit` and only ever edits that copy. The result is then
moved or copied back to the folder the source came from.

Status: **in progress**. The staged editor (`c23a4d38d`), the visible edits
(`bc6f41611`) and the move/copy back with records (`e6c76c8f1`) are on
`avest-dev`; nothing is released.

## Scope

In scope:

- open the built-in ReFra editor or a system editor on a staged copy;
- record every file the edit produced;
- move or copy an edited output back to the source folder, with rename or
  replace on conflict;
- discard the staged copies;
- list the files a session still holds.

Out of scope:

- editing the original in place;
- editing a file that already lives in the staging tree;
- syncing records with a third-party app's private output list.

## Version facts

| Fact | Value |
| --- | --- |
| Staging folder | `Pictures/aves_refra_edit` (one folder for every session) |
| Staging tree predicate | `isRefraEditStagingPath` |
| Output kinds | `staged`, `builtIn`, `external`, `unknown` |
| Session status | `active`, `moved`, `copied`, `discarded` |
| File identity | media id, then path, then name + size |
| Entry points | viewer edit action, Settings › ReFra edit |

## Reading order

1. `spec.md` — what the feature must do.
2. `rules.md` — the case register.
3. `decisions/` — why a transfer never offers the unedited copy, and why a
   partial delete commits per file.
4. `testing.md` — gates and device checks.

## Code map

| Layer | Path |
| --- | --- |
| Model | `lib/features/refra_edit/model/` |
| Store | `lib/features/refra_edit/db/` |
| Service | `lib/features/refra_edit/services/refra_edit_service.dart` |
| Views | `lib/features/refra_edit/view/` |
| Native staging | `android/app/src/main/kotlin/deckers/thibault/aves/channel/calls/MediaEditHandler.kt` |
| Tests | `test/features/refra_edit/` |

## Privacy note

Every path in this directory is a stand-in. See `docs/README.md`.
