# Selection XOR range — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-selection-xor-rules.ps1` resolves every `F:`
token.

## Interval

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| XOR-1 | Forward flip | WHEN the anchor is before the target, THE SYSTEM SHALL flip the rows after the anchor through the target | one gesture must pick a long run | `F:selection_xor_test#flips every item after the anchor up to the target` |
| XOR-2 | Backward flip | WHEN the anchor is after the target, THE SYSTEM SHALL flip the rows before the anchor through the target | the gesture must read the same in both directions | `F:selection_xor_test#flips backwards as well as forwards` |
| XOR-3 | Ranging back | WHEN the user ranges back over an interval just added, THE SYSTEM SHALL unselect exactly that interval and keep both endpoints | a mis-aimed range must be undoable by the same gesture | `F:selection_xor_test#ranging back undoes the interval it crossed before` |
| XOR-4 | Endpoint survives | WHEN an interval is flipped, THE SYSTEM SHALL leave the anchor's own state unchanged | the anchor is the fixed end, not part of the run | `F:selection_xor_test#flips every item after the anchor up to the target` |
| XOR-5 | Target follows | WHEN an interval is flipped, THE SYSTEM SHALL move the anchor to the target | the next range or drag continues from what was touched last | `F:selection_xor_test#flips every item after the anchor up to the target`; `F:selection_xor_test#ranging back undoes the interval it crossed before` |

## Degradation

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| XOR-6 | No anchor | WHEN the selection has no anchor, THE SYSTEM SHALL toggle the target alone | a declared mark or a section pick has no order to range from | `F:selection_xor_test#a selection with no anchor toggles the target alone` |
| XOR-7 | Anchor missing | WHEN the anchor is not in the ordered list, THE SYSTEM SHALL toggle the target alone | index arithmetic on a filtered list would hit a neighbour | `F:selection_xor_test#an anchor outside the ordered list toggles the target alone` |
| XOR-8 | Target missing | WHEN the target is not in the ordered list, THE SYSTEM SHALL toggle it alone | the row may have been filtered out between press and list | `F:selection_xor_test#a target outside the ordered list toggles it alone` |
| XOR-9 | Anchor pressed | WHEN the pressed row is the anchor, THE SYSTEM SHALL toggle it | an empty interval would look like a dead gesture | `F:selection_xor_test#pressing the anchor again toggles it instead of doing nothing` |

## Identity and rows

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| XOR-10 | Key comparison | WHEN the anchor is resolved, THE SYSTEM SHALL compare by key, not identity | the grid rebuilds its list from fresh instances | `F:selection_xor_test#resolves the anchor and the target by key, not by instance` |
| XOR-11 | Unselectable rows | WHEN an unselectable row is absent from the ordered list, THE SYSTEM SHALL skip it without shifting the interval | an index computed against the visible list must not reach a hidden row | `F:selection_xor_test#an unselectable row between the endpoints is not part of the interval` |

## Declared mark

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| XOR-12 | Mark without enumeration | WHEN the selection is a declared mark, THE SYSTEM SHALL flip its interval through the mark | marking a whole scope must not materialize it | `F:selection_xor_test#an interval flips through the mark without enumerating it` |
| XOR-13 | Emptied mark | WHEN an interval empties the mark, THE SYSTEM SHALL leave selection mode without an anchor | a leftover anchor would let the next press range from a page that is not selecting | `F:selection_xor_test#an interval that empties the mark leaves selection mode without an anchor` |

## Anchor lifecycle

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| XOR-14 | Toggle moves it | WHEN a tap toggles a row, THE SYSTEM SHALL make it the anchor | the last touched row is the range origin | `F:selection_test#the last single toggle becomes the anchor` |
| XOR-15 | Added range keeps it | WHEN rows are added through `addToSelection`, THE SYSTEM SHALL not move the anchor | an added range is not a touch | `F:selection_test#an added range does not move the anchor` |
| XOR-16 | Browse drops it | WHEN the selection leaves selection mode, THE SYSTEM SHALL drop the anchor | a new selection starts from nothing | `F:selection_test#leaving selection mode clears the anchor` |
| XOR-17 | Clear drops it | WHEN the selection is cleared, THE SYSTEM SHALL drop the anchor | same | `F:selection_test#clearing the selection clears the anchor` |
| XOR-18 | Mark drops it | WHEN a whole-scope mark is declared, THE SYSTEM SHALL drop the anchor | a mark has no item order | `F:selection_test#a whole-scope mark has no anchor to range from` |

## Gesture seam

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| XOR-19 | One seam | WHEN a grid supports multi-select, THE SYSTEM SHALL route its tap and long press through `GridSelectionGestureDetector` | a per-page copy would drift from the XOR rules | `F:selector_test#a long press subtracts the app bar and the pinned header`; `F:selector_test#without a header the press lands one header lower` |
| XOR-20 | Tap during scroll | WHEN a scroll is in progress, THE SYSTEM SHALL not toggle on a tap | the gesture that stops a fling must not pick a row | `-:needs scroll physics and timers; device-level` |
| XOR-21 | Paint-drag stays separate | WHEN a long press turns into a drag, THE SYSTEM SHALL settle the interval and then paint from the pressed row | unifying the two would double-flip the first painted row | `-:layout and timers; device-level` |
| XOR-22 | Cross-grid scope | WHEN a page scopes the selection to one grid, THE SYSTEM SHALL ignore a press in another grid | the two grids are two lists, not one range | `F:selector_test#the selection scope keeps a press from the other grid` |
| XOR-23 | Unselectable press | WHEN a press lands on a row outside the selectable list, THE SYSTEM SHALL start no selection | a summary or header row is not a selectable tile | `F:selector_test#a row outside the selectable list does not start a selection` |
