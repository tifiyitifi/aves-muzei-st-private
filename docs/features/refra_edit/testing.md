# ReFra edit — testing

## Gates

| Gate | Command | Question |
| --- | --- | --- |
| Analysis | `.flutter/bin/flutter.bat analyze` | does it type-check under the repo lints |
| Host tests | `.flutter/bin/flutter.bat test test/features/refra_edit` | do the staging, record and delete rules hold |
| Android build | `./flutterw build apk --profile -t lib/main_custom.dart --flavor custom` | does the staging handler compile |
| Rule register | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-refra-edit-rules.ps1` | does every `F:` token resolve |
| Device checklist | below | does it work with a real editor |

## Fixtures

`test/features/refra_edit/refra_edit_service_test.dart` drives the service against
an in-memory database with fake media-edit and media-fetch services. The service
takes its dependencies as optional constructor parameters for exactly this; the
process-wide services stay the production default.

## Device checklist

1. Edit a photo in the built-in editor and save a copy. Move the result back.
   Expect only the edited file to move; the unedited staged copy stays.
   (`EDI-3`, `EDI-4`)
2. Edit a photo and overwrite the staged copy in place, then move back. Expect
   the edited sibling to move. (`EDI-3`)
3. Copy a result back to the source folder. Expect the records page to point at
   the copied file, not the staging file. (`EDI-5`)
4. Delete two results, one of which is locked by another app. Expect the other
   one gone, the locked one still listed, and the session still open. (`EDI-9`)
5. Discard a session. Expect its staged files gone and the session forgotten.
   (`EDI-10`)
6. Try to edit a file that already lives in `Pictures/aves_refra_edit`. Expect
   the refusal. (`EDI-2`)

## Privacy

Describe a photo by kind, never by real file name or path.
