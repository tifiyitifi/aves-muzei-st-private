# Decision records

Append-only. A decision keeps its text when it is reversed; it gains a
`Superseded by` line and the new record explains why.

| Record | Decision |
| --- | --- |
| [0001](0001-results-live-in-the-database.md) | A result is actionable only through a database row |
| [0002](0002-a-run-never-modifies-an-original.md) | A run writes only the results folder |
| [0003](0003-replace-previous-parks-the-old-result.md) | Park the older result before reusing its name |
| [0004](0004-replace-overwrites-in-place-with-a-write-request.md) | Replace in place, with one write request per batch |
| [0005](0005-no-delete-action-in-the-results-view.md) | The results UI has no delete action |
| [0006](0006-the-results-folder-is-an-app-album.md) | The results folder is an app album, pinned once |
| [0007](0007-copy-share-reuses-the-engine.md) | Copy & share reuses the engine, separated by the output path |
| [0008](0008-the-result-carries-the-source-exif.md) | A result carries the source's capture metadata |
| [0009](0009-no-undo-history-in-v1.md) | v1 has no undo history |
| [0010](0010-profiles-share-one-table-by-kind.md) | Profiles share one table, keyed by kind |
| [0011](0011-record-on-item-done.md) | Record on `itemDone`, not at the end of the job |
| [0012](0012-share-output-is-temporary.md) | Share output is temporary and lives in its own folder |
| [0013](0013-no-auto-share-sheet.md) | A share run does not open the share sheet |
