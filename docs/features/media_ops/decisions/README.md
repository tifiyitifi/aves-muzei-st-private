# Media operations — decisions

Append-only records. A reversed decision keeps its text and gains a
`Superseded by` line.

| ID | Decision |
| --- | --- |
| [`0001-fallback-never-drops-the-source.md`](0001-fallback-never-drops-the-source.md) | A fallback that cannot read the source fails; it never creates an empty target or deletes the source |
| [`0002-one-refusal-is-not-a-provider-limitation.md`](0002-one-refusal-is-not-a-provider-limitation.md) | `REFUSED` falls back for one entry; only `UNSUPPORTED` disables the row path for the batch |
