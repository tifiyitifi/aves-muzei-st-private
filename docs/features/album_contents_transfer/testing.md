# Album contents transfer — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Host tests | `.flutter/bin/flutter.bat test test/features/album_contents_transfer` | do the plan/scope/rename rules hold |
| Android build | `./flutterw build apk --profile -t lib/main_custom.dart --flavor custom` | does `AlbumRename.kt` compile |
| Rule register | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-album-contents-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it work where the folders really are |

## What the host cannot hold

The native folder rename, its two-step temporary name and the per-entry outcome
of `doQuickMove` need real storage. `rules.md` marks those rows `M` or `-:`.

## Device checklist

1. Rename a stored album in the app's private storage. Expect the folder and the
   album state to move together. (`REN-5`)
2. Rename an album on shared storage with the folder grant. Expect one platform
   call, no per-file progress. (`REN-1`)
3. Rename an album whose folder is on a provider that refuses the folder rename.
   Expect the batched move and no `(1)` duplicates. (`REN-3`)
4. Block every file move in the batched fallback (for example by revoking the
   grant mid-run). Expect the album name to stay on the old folder. (`REN-9`)
5. Rename only the case of an album on a case-insensitive volume. Expect the
   folder renamed once, through the temporary name. (`REN-2`, `REN-10`)
6. Narrow the view so some rows are hidden, then try to rename. Expect the
   refusal and the offer to move the visible set. (`REN-7`)
7. Move the visible contents of two albums into a third; confirm the emptied
   source folders are removed and the destination's existing files survive.
   (`PLA-1`, `CLN-1`)

## Privacy

Describe albums and photos by kind, never by real name or path.
