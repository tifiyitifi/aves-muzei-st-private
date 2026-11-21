# ReFra edit — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## Copy first

- WHEN a session starts, THE SYSTEM SHALL copy the source into the staging
  folder and SHALL record the copy.
- WHEN the source already lives in the staging tree, THE SYSTEM SHALL reject the
  session.
- WHEN a cancelled editor produced no new file, THE SYSTEM SHALL drop the
  unedited copy.

## Results

- WHEN an editor writes a new file, THE SYSTEM SHALL record it as an output.
- WHEN the session page lists a result, THE SYSTEM SHALL resolve its media
  entry, adding one when the scanner has not.
- WHEN a copied file lands somewhere else, THE SYSTEM SHALL rewrite the output's
  URI, path, name and size.

## Transfer back

- WHEN the user transfers a session back, THE SYSTEM SHALL act only on edited
  outputs when the unedited staged copy is still present.
- WHEN the transfer is a move, THE SYSTEM SHALL delete the output rows of the
  files that moved.
- WHEN the transfer is a copy, THE SYSTEM SHALL keep the session usable.
- WHEN a file name conflicts, THE SYSTEM SHALL apply the strategy the user chose,
  and a replace is always an explicit decision.

## Deletion

- WHEN a file is deleted, THE SYSTEM SHALL commit that file's row.
- WHEN another file of the same request cannot be deleted, THE SYSTEM SHALL keep
  its row and report the partial result.
- WHEN a session loses its last output, THE SYSTEM SHALL forget the session.
