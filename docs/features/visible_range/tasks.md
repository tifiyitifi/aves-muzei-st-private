# Visible range — open work

No open correctness work. The items below are follow-ups found while writing the
register, in priority order.

| Item | Why | Rule |
| --- | --- | --- |
| Device pass over the page and the group editor | the layout, the draft prompt and the bar placement only meet their real surroundings on a device | `PAGE-1`, `GRP-6`, `NAV-6` |
| Host widget test for the group editor's draft/discard path | the controller save and the pure layout are covered; the page's close prompt is only exercised manually | `GRP-6` |
| Replace the `debugPrint` in `VisibleRangeFilterCodec.decode` with the fork logger | the fork's logging rule asks new code to use `lib/features/logging/`; a corrupt row is worth a channel log | `C5` (recurrences) |
| Host test for the trash exemption in `VisibleRangeGate.apply` | the exemption is documented but only exercised on a device | `GAT-4` |
| Host test for a page re-publishing an equal overlay | the token rule is covered; the equal-value path is asserted only through the notifier test | `GAT-6`, `GAT-10` |
| Decide whether the lock should block a bulk delete that mixes in-range and out-of-range entries | today the action is allowed or refused as a whole | `LCK-5`, `LCK-6` |

Not planned: a password or biometric lock. The lock is documented as casual
protection inside Aves (`0004`).
