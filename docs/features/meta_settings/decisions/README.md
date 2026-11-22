# Metadata settings engine — decisions

Append-only records. A reversed decision keeps its text and gains a
`Superseded by` line.

| ID | Decision |
| --- | --- |
| [`0001-the-gate-is-not-a-setting.md`](0001-the-gate-is-not-a-setting.md) | The engine selector lives in `SharedPreferences`, outside the settings key space |
| [`0002-seeding-is-one-shot-but-resumable.md`](0002-seeding-is-one-shot-but-resumable.md) | The seed copies only missing keys and writes its marker after a complete pass |
| [`0003-a-switch-replays-the-diff.md`](0003-a-switch-replays-the-diff.md) | A committed switch replays the differing keys before the surface swaps |
| [`0004-generic-writes-leave-the-guard-in-the-engine.md`](0004-generic-writes-leave-the-guard-in-the-engine.md) | Generic defs write through the engine; `custom` editors call typed setters directly |
