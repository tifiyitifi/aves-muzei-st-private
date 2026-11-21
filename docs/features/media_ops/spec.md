# Media operations — spec

Acceptance criteria in EARS form. `rules.md` turns each one into a case with
evidence.

## Engine and settings

- WHEN media operations run, THE SYSTEM SHALL default to the fast pipeline and
  SHALL keep the legacy pipeline selectable.
- WHEN the stored engine name is unknown, THE SYSTEM SHALL fall back to the fast
  pipeline.
- WHEN the user switches the engine, THE SYSTEM SHALL notify listeners once per
  actual change.

## Choosing an API

- WHEN a move stays on one volume and the entry is a Media Store row, THE SYSTEM
  SHALL update the row in place and SHALL NOT scan the file.
- WHEN the row cannot be updated but the file is accessible, THE SYSTEM SHALL
  move the file and clear the stale row.
- WHEN neither the row nor the file is writable, THE SYSTEM SHALL copy through
  the SAF provider and then remove the source.

## Fallback safety

- WHEN the fallback cannot open the source stream, THE SYSTEM SHALL fail the
  entry and SHALL NOT create an empty target or delete the source.
- WHEN a row update is refused for one entry, THE SYSTEM SHALL fall back for that
  entry only and SHALL keep trying the row path for the rest of the batch.
- WHEN a fallback moved the file, THE SYSTEM SHALL clear the old row even when
  the direct delete is refused.

## Permissions

- WHEN a write needs scoped-storage access, THE SYSTEM SHALL ask once for the
  selection before the first write.
- WHEN the user denies the request, THE SYSTEM SHALL remember the denial and
  SHALL NOT ask again for the same operation.
