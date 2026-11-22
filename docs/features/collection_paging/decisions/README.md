# Collection paging — decisions

Append-only records. A reversed decision keeps its text and gains a
`Superseded by` line.

| ID | Decision |
| --- | --- |
| [`0001-the-database-is-the-library.md`](0001-the-database-is-the-library.md) | A paged source keeps no entries; the database answers browsing, summaries and stats |
| [`0002-windows-never-block.md`](0002-windows-never-block.md) | A frame peeks the window cache and never awaits a fetch |
| [`0003-the-library-phase-moves-one-way.md`](0003-the-library-phase-moves-one-way.md) | One phase owns "browse or collection", and it never returns to browsing without a database reset |
| [`0004-the-catalogue-is-consent-once-per-session.md`](0004-the-catalogue-is-consent-once-per-session.md) | The background catalogue asks once per session and may be handed to the system service |
| [`0005-sync-advances-the-cursor-last.md`](0005-sync-advances-the-cursor-last.md) | The generation cursor advances only after changed rows and the retry list are persisted |
