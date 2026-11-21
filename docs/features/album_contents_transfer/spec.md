# Album contents transfer — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## Scope

- WHEN the user selects albums to transfer, THE SYSTEM SHALL act only on the
  entries the current visible range and hidden filters show.
- WHEN the scope cannot be compiled or is too large to materialize, THE SYSTEM
  SHALL refuse the action with an explanation instead of acting on a guess.

## Transfer

- WHEN the destination is inside one of the selected albums, THE SYSTEM SHALL
  reject the plan.
- WHEN the operation is a copy, THE SYSTEM SHALL not offer to delete the source
  folders.
- WHEN the source folders are emptied by a move, THE SYSTEM SHALL remove only
  directories that are completely empty.

## Rename

- WHEN a folder can be renamed in one platform call, THE SYSTEM SHALL rename the
  folder and then rewrite its rows.
- WHEN the folder rename is unsupported, THE SYSTEM SHALL fall back to the
  batched move.
- WHEN the platform renamed only some rows, THE SYSTEM SHALL sync the database
  before the batched path reads the old folder.
- WHEN the row rewrite fails after the folder moved, THE SYSTEM SHALL NOT move
  the album state to the new directory.
- WHEN the batched move moves no entry, THE SYSTEM SHALL NOT move the album
  state to the new directory.
- WHEN a folder only changes case, THE SYSTEM SHALL rename it through a
  temporary name.
- WHEN the visible range leaves rows behind, THE SYSTEM SHALL refuse the folder
  rename and offer a transfer of the visible set.
