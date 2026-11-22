# Selection XOR range — requirements

## Tap

- WHEN the user taps a row while already selecting, THE SYSTEM SHALL toggle that
  row.
- WHEN a tap toggles a row, THE SYSTEM SHALL move the anchor to it.
- WHEN the user taps while not selecting, THE SYSTEM SHALL enter selection mode
  and select that row.
- WHEN a tap deselects a row, THE SYSTEM SHALL still move the anchor to it.

## Long press

- WHEN the user long-presses a row while selecting, THE SYSTEM SHALL flip every
  row between the anchor and the pressed row.
- WHEN the interval is computed, THE SYSTEM SHALL exclude the anchor from the
  flip.
- WHEN the interval is computed, THE SYSTEM SHALL include the pressed row in the
  flip.
- WHEN the interval is forward, THE SYSTEM SHALL flip from the row after the
  anchor through the pressed row.
- WHEN the interval is backward, THE SYSTEM SHALL flip from the pressed row
  through the row before the anchor.
- WHEN a row inside the interval is selected, THE SYSTEM SHALL unselect it.
- WHEN a row inside the interval is unselected, THE SYSTEM SHALL select it.
- WHEN the flip is done, THE SYSTEM SHALL move the anchor to the pressed row.
- WHEN the user ranges back over an interval just added, THE SYSTEM SHALL
  unselect exactly that interval and leave both endpoints as they were.
- WHEN two ranges are performed in sequence, THE SYSTEM SHALL compose their flips
  instead of replacing the selection.

## Degradation

- WHEN the selection has no anchor, THE SYSTEM SHALL toggle the pressed row
  alone.
- WHEN the anchor is missing from the ordered list, THE SYSTEM SHALL toggle the
  pressed row alone.
- WHEN the pressed row is missing from the ordered list, THE SYSTEM SHALL toggle
  it alone.
- WHEN the pressed row is the anchor, THE SYSTEM SHALL toggle it and keep it as
  the anchor.
- WHEN the selection is a whole-scope mark with no anchor, THE SYSTEM SHALL
  toggle the pressed row alone.

## Identity and scope

- WHEN the anchor is compared with a list row, THE SYSTEM SHALL compare by key,
  not by object identity.
- WHEN the interval is applied, THE SYSTEM SHALL act on the instances held by the
  ordered list.
- WHEN unselectable rows are absent from the ordered list, THE SYSTEM SHALL skip
  them without shifting the interval onto their neighbours.
- WHEN an interval flip empties a declared mark, THE SYSTEM SHALL leave selection
  mode and drop the anchor.
- WHEN a page scopes the selection to one grid, THE SYSTEM SHALL not range into
  another grid's rows.
- WHEN a press lands outside the page's selection scope, THE SYSTEM SHALL toggle
  nothing.

## Paint-drag

- WHEN a long press is followed by a drag, THE SYSTEM SHALL paint from the pressed
  row with the existing add/erase logic.
- WHEN a long press is followed by a drag, THE SYSTEM SHALL settle only the
  interval flip and leave the rest of the drag to the paint logic.

## Anchor lifecycle

- WHEN the selection leaves selection mode, THE SYSTEM SHALL drop the anchor.
- WHEN the selection is cleared, THE SYSTEM SHALL drop the anchor.
- WHEN a whole-scope mark is declared, THE SYSTEM SHALL drop the anchor.
- WHEN a range is added through `addToSelection`, THE SYSTEM SHALL leave the
  anchor unchanged.

## Non-goals

- WHEN a single item is picked from a picker page, THE SYSTEM SHALL not offer a
  range gesture.
- WHEN the viewer toggles one entry, THE SYSTEM SHALL not involve the range.
