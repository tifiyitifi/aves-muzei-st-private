# 0003 — Park the older result before reusing its name

Status: accepted (`3c827fe54`)

## Context

In replace-previous mode a new result should take the source's plain name. The
MediaStore does not overwrite on insert: when the name is taken it writes
`name (1).jpg` instead. Writing the new result first therefore produces a second
file with a suffix, and "one pending result per source" becomes false.

Deleting the old file first is worse: if the new write then fails, the only copy
is gone.

## Decision

Order the sequence so the name is freed without ever deleting the only copy:

1. insert and record the new result;
2. rename the older pending file to `<base>-to-remove.<ext>`;
3. delete the parked file;
4. rename the new result to `<base>.<ext>`;
5. rewrite the new row's URI, path, name, MIME and size.

A failure at any step leaves both files on disk.

## Consequences

- A rerun never produces a ` (1)` duplicate (`R1`).
- For a moment the folder holds two files, one of them parked. A later run
  prunes parked files it knows about.
- The parked name is not a user-facing state: it exists to free a name, not to
  keep a version.
- Keep-versions mode does not use this path; it gives every result a distinct
  name and keeps them all pending.
