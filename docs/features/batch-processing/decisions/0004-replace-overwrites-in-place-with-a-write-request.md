# 0004 — Replace in place, with one write request per batch

Status: accepted (`3c827fe54`)

## Context

"Replace the original" could be implemented as: copy the result back to the
source folder, delete the source, let the scanner reindex. That changes the
source's identity: albums, favourites, tags, covers and the app's own row all
reference the source, and a reindexed file gets a new content id. A same-volume
row update is also much cheaper than a scan, which is why the media-ops engine
prefers it (`239ea4a40`).

Scoped storage refuses a write to a file the app does not own until the user
grants access. Asking per file would mean one system dialog per photo; the
existing media-ops engine already escalates once for the remaining batch
(`2afb33613`).

## Decision

Replace overwrites the source bytes in place through `overrideImageStreaming`,
which keeps the source row's date columns and restores the original bytes if the
write fails. When the result's display name differs, the source row takes the
result's name and MIME type. The result file is consumed. Write access is
requested once, for the whole selection, before the first write.

## Consequences

- Albums, favourites and tags keep pointing at the same source.
- A format change cannot leave a PNG labelled `.jpg` (`R4`).
- The replacement is destructive and has no undo; the confirmation dialog says
  so.
- A failed write leaves the result pending, so the user can retry or move it
  back instead (`APP-2`).
- The 2000-URI cap of `MediaStore.createWriteRequest` is handled by chunking,
  not by asking per file.
