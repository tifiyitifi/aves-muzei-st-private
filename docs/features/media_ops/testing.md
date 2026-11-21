# Media operations — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Host tests | `.flutter/bin/flutter.bat test test/features/media_ops` | do the engine/outcome/prefs rules hold |
| Android build | `./flutterw build apk --profile -t lib/main_custom.dart --flavor custom` | does the native pipeline compile |
| Rule register | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-media-ops-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it work where the files really are |

## What the host cannot hold

`MediaOpV2.kt` talks to the Media Store and the file system. Its fallback order,
its permission retries and its row cleanup have no host fixture; `rules.md`
marks them `M` or `-:` instead of pretending.

## Device checklist

1. Move a photo within one volume. Expect no scanner pass and the album counts
   updated. (`SAFE-2`)
2. Move a photo across volumes. Expect the file moved and the old row gone.
   (`SAFE-3`)
3. Rename a photo on a provider that refuses `TITLE`. Expect the fallback to
   rename the file and clear the old row, and the next entry in the batch to
   still try the row path. (`SAFE-4`)
4. Move a photo that is still being written by another app. Expect the entry to
   fail; the source must still exist and no empty file must appear. (`SAFE-1`)
5. Deny the write request once. Expect no second prompt for the same operation.
   (`OUT-3`)

## Privacy

Describe a photo by kind (`a photo from the camera album`), never by file name.
