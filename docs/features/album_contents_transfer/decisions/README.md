# Album contents transfer — decisions

Append-only records. A reversed decision keeps its text and gains a
`Superseded by` line.

| ID | Decision |
| --- | --- |
| [`0001-the-album-state-follows-the-rows.md`](0001-the-album-state-follows-the-rows.md) | The album state moves only after the rows did; a folder rename whose rows failed stays unapplied |
| [`0002-a-probe-failure-keeps-the-old-behaviour.md`](0002-a-probe-failure-keeps-the-old-behaviour.md) | An unreadable visibility probe allows the rename instead of refusing on a guess |
