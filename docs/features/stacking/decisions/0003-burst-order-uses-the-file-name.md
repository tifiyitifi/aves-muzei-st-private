# Burst order uses the file name, never the title

Status: accepted.

## Context

The legacy lens sorts a burst with `AvesEntrySort.compareByName`, which reads
`bestTitle` — a metadata title when one exists, the file name otherwise.

## Decision

The fork's policy compares the file base name (`compareAsciiUpperCaseNatural`),
then the extension, and never consults metadata.

## Why

- A title on one frame of a burst is exotic, and the catalogue writes metadata
  after the first page is already visible; the tile would move under the user.
- The persisted index is written from the media store, where a title may not be
  known at all.
- File names are the same on every device, so the tile is reproducible.

## Consequences

- A burst with non-ASCII names sorts by code unit, which can look arbitrary to a
  locale-aware reader; that is the inherited file ordering.
- A future "tile the newest frame" request is not a one-line change: `StackRow`
  would need a date field and the decision would need revisiting.

## Alternatives rejected

- `bestTitle`: metadata-dependent and arrives late.
- Locale collation: the persisted key and tile would differ per device.
