# ReFra edit — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-refra-edit-rules.ps1` resolves every `F:` token.

## Staging

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| EDI-1 | One folder | WHEN a session starts, THE SYSTEM SHALL stage into the one shared folder | `bc6f41611` | `F:refra_edit_store_test#every session stages into the same album folder` |
| EDI-2 | Tree predicate | WHEN a path names the staging tree, THE SYSTEM SHALL recognise it however it is written | a `\` path and a sibling prefix must not match | `F:refra_edit_store_test#the staging tree is recognised however its path is written` |
| EDI-3 | Transfer scope | WHEN the unedited staged copy sits next to an edited output, THE SYSTEM SHALL not offer it for transfer | replacing the original with the unedited copy loses the edit | `F:refra_edit_service_test#a transfer offers only edited outputs when an unedited copy remains` |
| EDI-4 | Move back | WHEN a session moves back, THE SYSTEM SHALL send only edited outputs to the move | the staged copy is the source's duplicate | `F:refra_edit_service_test#moving back leaves the unedited staged copy out of the transfer` |

## Results

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| EDI-5 | Copy follows the file | WHEN a copy lands elsewhere, THE SYSTEM SHALL rewrite the output's URI and path | the record must name the file the user got | `F:refra_edit_service_test#copying back rewrites where each output lives` |
| EDI-6 | Store rewrite | WHEN an output location is rewritten, THE SYSTEM SHALL persist URI, path and size | the records page reads the row, not the file | `F:refra_edit_store_test#an output location is rewritten after a transfer` |

## Sessions and deletion

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| EDI-7 | Move status | WHEN every kept output moved, THE SYSTEM SHALL mark the session moved | a moved session has nothing left to open | `F:refra_edit_store_test#moving back marks the session and keeps its history` |
| EDI-8 | Copy status | WHEN a copy landed, THE SYSTEM SHALL keep the session usable | the staged copies are still there | `F:refra_edit_store_test#copying back keeps the session usable` |
| EDI-9 | Partial delete | WHEN some files cannot be deleted, THE SYSTEM SHALL commit the ones that were and keep the rest | a single failure used to abort every row | `F:refra_edit_service_test#a partial delete commits the files that were removed and keeps the rest` |
| EDI-10 | Last output | WHEN a session loses its last output, THE SYSTEM SHALL forget the session | an empty session has no file to act on | `F:refra_edit_store_test#deleting the last output forgets its session` |
| EDI-11 | Source directory | WHEN a record has no source directory outside the staging tree, THE SYSTEM SHALL not offer a transfer back | moving into the staging tree only renames the copy | `F:refra_edit_store_test#a record can only go back to a source folder outside the staging tree` |
