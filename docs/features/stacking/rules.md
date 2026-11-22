# Stacking — rule register

One row per case this slice owns. Coverage tokens are defined in `docs/README.md`;
`scripts/check-stacking-rules.ps1` resolves every `F:` token.

The paged and persistence halves are registered where they are implemented:
`LEN-28`/`LEN-29` (`collection_paging`) for hiding a member and the calendar
layout, `QRY-6`/`QRY-8`/`MIG-3` (`drift_db`) for settling, re-homing, renaming
and the v4 backfill. This register owns the policy those rows apply.

## Group key

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STK-1 | Base name | WHEN a row has a path, THE SYSTEM SHALL take the file name without its last extension | a burst is recognised by its name, not by metadata that may arrive late | `F:stack_grouping_test#a base name is the file name without its extension` |
| STK-2 | Keyless without a path | WHEN a row has no path, THE SYSTEM SHALL give it no base name | a path-less row cannot be in a folder, so it cannot share a burst | `F:stack_grouping_test#a base name is the file name without its extension` |
| STK-3 | Burst key | WHEN the base name matches a configured pattern, THE SYSTEM SHALL key the row as `<directory>/<burst key>` | two folders must never share a burst, even with identical timestamps | `F:stack_grouping_test#the burst key needs a directory, a base name and a matching pattern` |
| STK-4 | Missing inputs | WHEN the directory is missing, no pattern matches, or the pattern list is empty, THE SYSTEM SHALL leave the row keyless | a guessed key would merge unrelated files | `F:stack_grouping_test#the burst key needs a directory, a base name and a matching pattern` |
| STK-5 | Pattern change | WHEN the patterns change, THE SYSTEM SHALL rebuild the keys and re-settle the tiles | the key is persisted, so it must follow the configuration | `F:entry_stack_test#a pattern change rebuilds the keys and re-settles the tiles` |

## Representative

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STK-6 | First frame | WHEN a burst group has several members, THE SYSTEM SHALL tile the first by natural base-name order | the tile must not depend on write order or on which frame was catalogued first | `F:stack_grouping_test#a burst tiles its first frame by natural name` |
| STK-7 | Extension tie | WHEN two members share a base name, THE SYSTEM SHALL break the tie by extension | a burst frame and its developed copy can share a name | `F:stack_grouping_test#the extension breaks a name tie` |
| STK-8 | Developed over RAW | WHEN a keyless group holds a RAW and a developed image of the same base name, THE SYSTEM SHALL hide the RAW and tile the developed image | the user wants the processed picture, not the negative | `F:stack_grouping_test#without a burst the developed image hides its raw sibling` |
| STK-9 | No survivor | WHEN a group has no single surviving member, THE SYSTEM SHALL show every member | with no defensible representative, showing both is honest | `F:stack_grouping_test#keyless raws without a developed image all show` |

## Group identity

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STK-10 | Rename | WHEN a directory is renamed, THE SYSTEM SHALL move the group and keep its tile | which member shows is a property of the group, not of its path | `F:entry_directory_rename_test#moves a burst group together, keeping its key shape and its tile` |

## Boundaries

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| STK-11 | Presentation order | WHEN a burst stack is presented, THE SYSTEM SHALL order its members by the policy's comparison | the viewer pages through the stack in the same order as the burst | `F:paged_stack_test#a burst shows one tile carrying its frames` |
| STK-12 | Member order below | WHEN a developed-RAW stack is presented, THE SYSTEM SHALL list the developed image first | the processed copy is what the stack means | `F:entry_stack_test#a developed stack lists the developed image before its raw` |
| STK-13 | Lone row | WHEN a group holds one row, THE SYSTEM SHALL not expose it as a stack | a badge on a single row lies about hidden frames | `F:entry_stack_test#a lone row is not a stack` |
| STK-14 | Late attachment | WHEN a window becomes visible, THE SYSTEM SHALL attach its members afterwards | one frame without a badge costs less than making every window wait | `F:paged_stack_test#a burst shows one tile carrying its frames` |
| STK-15 | Calendar owns its grouping | WHEN the layout is the calendar, THE SYSTEM SHALL group by day instead of by stack | a day row must not hide a frame from another view | `F:paged_stack_test#the calendar layout shows one row per day` |
