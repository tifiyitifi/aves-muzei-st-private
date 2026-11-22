# Drift database — decisions

Append-only records. A reversed decision keeps its text and gains a
`Superseded by` line.

| ID | Decision |
| --- | --- |
| [`0001-one-connection-for-settings-and-media.md`](0001-one-connection-for-settings-and-media.md) | The v2 settings store and the media DB share one connection |
| [`0002-migrations-are-forward-only-and-guarded.md`](0002-migrations-are-forward-only-and-guarded.md) | Each schema step is small, guarded, and has an upgrade test |
| [`0003-the-legacy-import-is-one-way.md`](0003-the-legacy-import-is-one-way.md) | `metadata.db` is read once and never written |
