# 0008 — A result carries the source's capture metadata

Status: accepted (`3c827fe54`)

## Context

The bake path decodes to a bitmap and encodes a new file. The re-encode has no
EXIF of its own. A result without the source's capture time, camera and location
is a different photo for every surface that sorts, searches or maps by metadata
— and replacing an original with such a result would silently destroy the
original's provenance.

## Decision

After writing a result, copy the source's EXIF tags onto it and reset the
orientation to normal, because the pixels are already upright. Best-effort: a
format the platform cannot tag keeps its pixels.

## Consequences

- A replaced original keeps its capture time and location (`R3`).
- A result sorts and maps like its source instead of looking like a file created
  today.
- Orientation is normal on the result; a viewer must not rotate it twice.
- Formats without EXIF support lose the tags; the run still succeeds.
