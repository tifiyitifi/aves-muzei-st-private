# Stacking — requirements

## The group key

- WHEN a row has a path, THE SYSTEM SHALL derive its base name as the file name
  without its last extension.
- WHEN a row has no path, THE SYSTEM SHALL give it no base name.
- WHEN the base name matches a configured burst pattern, THE SYSTEM SHALL key the
  row as `<directory>/<burst key>`.
- WHEN the directory is missing, THE SYSTEM SHALL leave the row keyless.
- WHEN no configured pattern matches, THE SYSTEM SHALL leave the row keyless.
- WHEN the pattern list is empty, THE SYSTEM SHALL leave every row keyless.
- WHEN the patterns change, THE SYSTEM SHALL recompute the keys and re-settle the
  groups.
- WHEN two directories hold the same burst key, THE SYSTEM SHALL keep them in
  separate groups.

## The representative

- WHEN a burst group has several members, THE SYSTEM SHALL tile the first by
  natural uppercase-ASCII base name.
- WHEN two base names are equal, THE SYSTEM SHALL break the tie by extension.
- WHEN the chosen tile already hides the other frames, THE SYSTEM SHALL not hide
  it behind a developed sibling that is itself hidden.
- WHEN a keyless group holds a RAW and a developed image of the same directory and
  base name, THE SYSTEM SHALL hide the RAW and tile the developed image.
- WHEN a keyless group holds only RAWs, THE SYSTEM SHALL hide nothing.
- WHEN a group has no single surviving member, THE SYSTEM SHALL show every member
  itself.
- WHEN a group settles, THE SYSTEM SHALL store the tile as the row without
  `stackTileId` and point every other member at it.

## Presentation

- WHEN a burst stack is presented, THE SYSTEM SHALL order its members by the same
  natural name and extension comparison.
- WHEN a developed-RAW stack is presented, THE SYSTEM SHALL list the developed
  image before the RAW.
- WHEN a group holds one row, THE SYSTEM SHALL not present it as a stack.
- WHEN a tile's window becomes visible, THE SYSTEM SHALL attach its members
  afterwards.

## Maintanance

- WHEN an entry is inserted, updated, moved or deleted, THE SYSTEM SHALL settle
  the groups it belongs to.
- WHEN a directory is renamed, THE SYSTEM SHALL keep the group's key shape and its
  tile.
- WHEN a burst pattern changes, THE SYSTEM SHALL rewrite every key and clear the
  tiles before re-settling them.

## Non-goals

- WHEN the layout is the calendar, THE SYSTEM SHALL group by day instead of by
  stack.
- WHEN an action or a selection expands a view, THE SYSTEM SHALL include the
  hidden members; that is the caller's contract, not the policy's.
