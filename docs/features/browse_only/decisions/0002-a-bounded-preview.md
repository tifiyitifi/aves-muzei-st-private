# The timeline is a bounded preview; only the user passes the limit

Status: accepted.

## Context

The browser could page the whole library into memory, or stop at a bound. The
library can hold tens of thousands of rows.

## Decision

The timeline reads a 5000-row preview (`previewRowLimit`). Automatic paging stops
there; the preview strip's button reads on (`loadMore(beyondPreviewLimit: true)`).
An album reads its folder whole, because a folder's count is already whole and
bounded by its own size.

## Why

- The browser exists because the collection cannot yet hold the library; growing
  it into the same in-memory list would defeat the point.
- 5000 rows is more than a browsing session reaches, so the limit is invisible
  until the user asks for more.
- A folder is a natural bound; a whole-library timeline is not.

## Consequences

- The preview strip tells the user the timeline is a preview and offers to
  continue.
- `atLimit` uses the raw row count, which includes hidden-album rows filtered out
  of the grid; the strip can therefore count a few rows the grid does not show.
- An action that needs the whole library is greyed rather than served from the
  preview.

## Alternatives rejected

- Reading the whole library: the memory and time cost the import exists to avoid.
- A much smaller limit: the strip would appear in ordinary browsing.
