# Metadata settings engine — open work

No open correctness work. The items below are completeness work, in priority
order, each linked to the rule it would strengthen.

| Item | Why | Rule |
| --- | --- | --- |
| Migration test for the `settingsValues` table against the previous fork schema | The v2 test upgrades from v1 of the app schema; a later schema bump must keep this table intact | `MIGR-1` |
| Port the remaining categories that still fall back to the fork-owned legacy section | A fallback category renders upstream widgets inside the v2 page | `CAT-4`, `CAT-9` |

Not planned: changing the synchronous `SettingsAccess.set` contract to report a
persistence failure. It is shared with v1; the accepted behaviour is documented
in `design.md` and `R4`.
