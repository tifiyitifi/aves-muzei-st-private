# ReFra edit — decisions

Append-only records. A reversed decision keeps its text and gains a
`Superseded by` line.

| ID | Decision |
| --- | --- |
| [`0001-a-transfer-never-sends-the-unedited-copy.md`](0001-a-transfer-never-sends-the-unedited-copy.md) | A move/copy back acts on edited outputs; the staged copy is only used when it is the sole output |
| [`0002-a-partial-delete-commits-per-file.md`](0002-a-partial-delete-commits-per-file.md) | Each deleted file loses its row; a failure keeps its row for a retry |
