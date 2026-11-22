# The preview counts what the grid shows

Status: accepted.

## Context

The strip under the timeline says "Timeline shows the newest {count} items". The
count used to be `BrowseLibrary.length`, the rows the window **read** from the
media store. The display order, however, drops hidden albums, so a user who hid a
large folder could read 5000 rows and see fewer: the strip claimed tiles that were
not on screen.

## Decision

The strip takes the displayed order's length (`order.length`). The preview limit
and `atLimit` keep counting rows read.

## Why

- The sentence is about what the timeline shows. A count that includes an
  invisible folder is wrong even when the tiles behind it exist.
- The limit protects memory and I/O: it is a budget on reads, so it must not move
  when the user hides or unhides a folder.
- The two numbers disagree by at most the hidden rows, and the strip is only a
  preview: stating the visible number is enough for the user to know where the
  rest is.

## Consequences

- A window at its limit with hidden albums states the smaller visible number and
  still stops at the raw limit; the hidden rows stay read (they were in the page
  the platform returned).
- Unhiding an album can grow the stated count without a new read.
- Reversing this is a rule change (`UI-6`), not an implementation detail.

## Alternatives rejected

- Counting the rows read: claims tiles the user cannot see.
- Stopping the reads once the displayed count reaches the limit: makes the limit
  depend on the hidden-album setting, so hiding a folder would shrink the window
  and unhiding it would need a re-read.
