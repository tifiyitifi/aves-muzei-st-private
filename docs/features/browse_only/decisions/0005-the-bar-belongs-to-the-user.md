# The bar is the user's, and the drawer is fail-closed

Status: accepted.

## Context

Browsing cannot serve every destination: a tag page, a rating filter or a trash
view needs the catalogued database. The bar and the drawer must show that without
hiding the app's shape.

## Decision

The bottom bar renders the user's own navigation, appending the visible-range
destination once, and dims any entry it cannot serve with no tap handler. The
drawer keeps every entry and decides `enabled` through a whitelist: organized
enables everything, browsing enables the media-store-backed entries and greys
everything else, including a destination the whitelist does not know.

## Why

- A fixed four-entry bar was tried and reverted: it replaced the user's own
  navigation for a temporary state.
- Showing a greyed entry preserves the map of the app; hiding entries would make
  the drawer look different for minutes.
- Fail-closed is the cheap direction: guessing wrong on an unknown route costs a
  broken view, greying it costs one disabled row.

## Consequences

- A new destination must be added to the whitelist deliberately or it is greyed
  while browsing.
- A greyed entry has no `InkResponse`, so it cannot flash a ripple that suggests it
  worked.
- The bar disappears when the user configured fewer than two items, even though
  the visible-range entry would make two.

## Alternatives rejected

- A fixed browsing bar: replaces the user's configuration.
- Hiding unservable entries: the app's shape changes for a temporary state.
