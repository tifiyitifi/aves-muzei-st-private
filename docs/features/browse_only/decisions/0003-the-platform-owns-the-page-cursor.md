# The platform owns the page cursor

Status: accepted.

## Context

MediaStore paging returns pages of rows, but the platform filters rows the app
never sees (pending, trashed, permission-denied). A Dart-side offset would drift
from what the provider returned.

## Decision

The page request carries a `MediaStorePageCursor` built from the values the
platform reported for the previous page (one key per collection, because images
and videos have independent id spaces). The Dart window stores and resends it.

## Why

- Only the platform knows how many rows it filtered out of a page, so only it can
  say where the next page starts.
- A numeric offset would skip or repeat rows whenever the provider filtered some.
- Per-collection keys keep images and videos correct despite colliding ids.

## Consequences

- An empty page with more rows is not the end: the window reads on with the new
  cursor.
- A cursor that does not advance is an error, not a retry loop.
- The keyset SQL lives in the native provider and is verified on a device.

## Alternatives rejected

- A row offset: wrong as soon as the provider filters.
- Reading until a short page: loses rows when the provider truncates.
