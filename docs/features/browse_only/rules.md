# Browse only — rule register

One row per case the feature has to get right. Coverage tokens are defined in
`docs/README.md`; `scripts/check-browse-only-rules.ps1` resolves every `F:` token.

## Placement

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| NAV-1 | Interim surface | WHEN the library phase is importing or failed, THE SYSTEM SHALL render the browser instead of the collection grid | a half-written database must not look like an empty library | `-:the seam is collection_page.dart and needs the whole collection page (see testing.md)` |
| NAV-2 | Never a pick surface | WHEN a pick is in progress, THE SYSTEM SHALL keep the collection grid | a pick cannot be completed in a browser that offers no selection | `-:the app-mode gate lives in collection_page.dart` |
| NAV-3 | Handoff | WHEN the library phase reaches ready, THE SYSTEM SHALL clear the browse window and album list | the collection takes over the bottom of the app | `-:the seam is collection_page.dart; the windows' own clear is covered by WIN-11 and ORD-9` |
| NAV-4 | Menu button | WHEN an outer scaffold owns a drawer, THE SYSTEM SHALL offer a button that opens it | the browser's own scaffold would hide the app drawer | `-:layout` |

## The paged window

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| WIN-1 | First page | WHEN the timeline reads its first page, THE SYSTEM SHALL request at most the page size with no cursor | the first read must be bounded | `F:browse_library_paging_test#the first page is one bounded read and the next one follows its cursor` |
| WIN-2 | Cursor | WHEN a later page is read, THE SYSTEM SHALL resume from the platform's cursor | only the platform knows what it filtered out | `F:browse_library_paging_test#the first page is one bounded read and the next one follows its cursor` |
| WIN-3 | Duplicates | WHEN a page repeats a row, THE SYSTEM SHALL ignore it | a cursor race must not duplicate a tile | `F:browse_library_test#keeps arrival order and ignores rows a page repeats` |
| WIN-4 | Trash | WHEN a page carries a trashed row, THE SYSTEM SHALL leave it out | the browser shows live media | `F:browse_library_test#leaves trashed rows out` |
| WIN-5 | Filtered page | WHEN a page is empty but more rows remain, THE SYSTEM SHALL read on | the platform filters rows the app never sees | `F:browse_library_paging_test#a page the platform filtered out is read past instead of stalling the window` |
| WIN-6 | Stalled cursor | WHEN the cursor cannot advance, THE SYSTEM SHALL stop with an error | asking again would loop forever | `F:browse_library_paging_test#a page whose cursor cannot advance stops with an error` |
| WIN-7 | Failure | WHEN a page read fails, THE SYSTEM SHALL keep the rows and stop paging | losing the window because of one page is worse than a short window | `F:browse_library_paging_test#a failed page keeps the rows and can be retried` |
| WIN-8 | Retry | WHEN the user retries, THE SYSTEM SHALL clear the error and resume | retry must continue, not restart | `F:browse_library_paging_test#a failed page keeps the rows and can be retried` |
| WIN-9 | Timeout | WHEN a page read never answers, THE SYSTEM SHALL report a timeout | a lost platform reply must not leave a spinner forever | `F:browse_library_paging_test#a page that never answers times out and can be retried` |
| WIN-10 | Preview limit | WHEN the window reaches its limit, THE SYSTEM SHALL stop until the user asks for more | the browser must not grow into the library the collection exists to hold | `F:browse_library_paging_test#the timeline stops at its preview limit and only the user passes it`; `F:browse_library_paging_test#the default timeline limit is 5000 and only the user passes it` |
| WIN-11 | Handoff race | WHEN the window is cleared while a page is in flight, THE SYSTEM SHALL discard that page | the handoff must not be undone by a late reply | `F:browse_library_paging_test#a page in flight cannot refill a window cleared for the handoff`; `F:browse_albums_test#a read landing after clear cannot refill the list` |
| WIN-12 | Clear notification | WHEN the window is cleared during its first read, THE SYSTEM SHALL notify its listeners | the view is showing a spinner it must remove | `F:browse_library_paging_test#clearing a window during its first read tells its listeners` |
| WIN-13 | Empty library | WHEN the library is empty, THE SYSTEM SHALL report an empty window, not an error | an empty library is a valid state | `F:browse_library_paging_test#an empty library loads as empty, not as an error` |
| WIN-14 | Exact multiple | WHEN a full page lands on the page size, THE SYSTEM SHALL confirm the end with one more read | the last page is not the end of the library | `F:browse_library_paging_test#an exact multiple of the page size ends with one empty read, not a lost row` |
| WIN-15 | Collection ids | WHEN two collections share a content id, THE SYSTEM SHALL page them independently | images and videos have separate id spaces | `F:browse_library_paging_test#two collections with colliding ids page without losing a row`; `F:browse_library_test#two collections sharing a content id are two rows` |
| WIN-16 | Disposed window | WHEN a window is disposed, THE SYSTEM SHALL not read | a disposed page must not run | `F:browse_library_paging_test#a disposed window does not read` |

## Order, sections and entries

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| ORD-1 | Date fallback | WHEN a row's sort date is read, THE SYSTEM SHALL fall back the way the SQL expression does | an unknown date is not zero | `F:browse_library_test#the sort date falls back the way the SQL expression does` |
| ORD-2 | Display order | WHEN the timeline is sorted, THE SYSTEM SHALL order by date or name, in both directions | the sort menu offers four pairs | `F:browse_library_test#orders the timeline by date or by name, both directions` |
| ORD-3 | Hidden albums | WHEN the media index is built, THE SYSTEM SHALL leave out hidden albums | a folder the user hid must not reappear | `F:browse_library_test#hides rows of hidden albums from the media grid too` |
| ORD-4 | Video narrowing | WHEN the index is narrowed to videos, THE SYSTEM SHALL filter without touching the database | a view filter must not re-read | `F:browse_library_test#narrows the index to videos without touching the database` |
| ORD-5 | Entry cache | WHEN a row is materialized, THE SYSTEM SHALL reuse the entry | the grid must not build an entry per build | `F:browse_library_test#materializes an entry on demand and reuses it` |
| ORD-6 | Synthetic ids | WHEN an entry is materialized, THE SYSTEM SHALL give it an id no database row can have | a viewer or selection keyed by id must not alias a real row | `F:browse_library_test#synthetic entry ids are unique and disjoint from database ids` |
| ORD-7 | Month sections | WHEN the grid is sectioned, THE SYSTEM SHALL emit a month header and then its rows | the grid is one flat list, not a sliver per month | `F:browse_library_test#groups the media grid into months, newest first`; `F:browse_grid_items_test#a month is a header followed by the rows of its tiles` |
| ORD-8 | Full coverage | WHEN the items are flattened, THE SYSTEM SHALL place every position once and never cross a month | a missing position is a blank cell | `F:browse_grid_items_test#the rows cover the order once, in order, and never cross a month` |
| ORD-9 | Handoff clear | WHEN the window is cleared, THE SYSTEM SHALL report itself empty and able to read again | the next library phase may need it | `F:browse_library_test#clears the window for the handoff back to the collection` |

## The scroller

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| SCR-1 | Geometry | WHEN months are laid out, THE SYSTEM SHALL place each start after the previous rows | the handle jumps to the wrong month otherwise | `F:browse_scroll_map_test#months start where their header does, and the list ends after the last row` |
| SCR-2 | Offset lookup | WHEN an offset is read, THE SYSTEM SHALL name its month and clamp outside the list | a handle at either end still needs a name | `F:browse_scroll_map_test#an offset names the month it is in, and clamps outside the list` |
| SCR-3 | Snap | WHEN a drag lands between months, THE SYSTEM SHALL snap to the nearer start | a handle between headers shows the wrong label | `F:browse_scroll_map_test#a drag snaps to the nearer month start` |
| SCR-4 | Crumbs | WHEN crumbs are shown, THE SYSTEM SHALL express month starts as fractions | the crumb rail must match the list | `F:browse_scroll_map_test#crumbs are the month starts as fractions of the list` |
| SCR-5 | Empty | WHEN there are no items, THE SYSTEM SHALL report no months and no fractions | an empty list has nothing to scroll | `F:browse_scroll_map_test#an empty list has no months and no fractions` |
| SCR-6 | Visibility | WHEN the sectioned timeline has fewer than four months, THE SYSTEM SHALL not show the handle | a short list does not need a rail | `F:browse_media_grid_test#a long timeline gets the drag handle, and a drag lands on a month` |

## Albums

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| ALB-1 | Aggregate read | WHEN the album view mounts, THE SYSTEM SHALL read the whole list once | a count must arrive whole, not grow | `F:browse_albums_test#the list arrives whole, with its counts and covers` |
| ALB-2 | Idempotent load | WHEN the list is already loaded, THE SYSTEM SHALL not read again | remounting a page must not rescan | `F:browse_albums_test#a second load does not re-read the list` |
| ALB-3 | Hidden albums | WHEN the user hides an album, THE SYSTEM SHALL re-derive the visible list without re-reading | hiding is a settings change, not a media change | `F:browse_albums_test#hides albums the user hid from the collection`; `F:browse_albums_test#hiding an album updates the loaded list without re-reading it` |
| ALB-4 | Same-named folders | WHEN two visible folders share a name, THE SYSTEM SHALL label each with its parent | two "Camera" tiles are indistinguishable | `F:browse_albums_test#disambiguates same-named folders on other paths` |
| ALB-5 | Album sort | WHEN albums are sorted, THE SYSTEM SHALL honour date, name or count and the direction | the menu offers six pairs | `F:browse_albums_test#orders albums by recency, name or item count` |
| ALB-6 | Failure | WHEN the aggregate read fails, THE SYSTEM SHALL report it with a retry | "no folders" would be a lie | `F:browse_albums_test#a failed read leaves the list empty and reports the error`; `F:browse_albums_test#a failed read can be retried` |
| ALB-7 | Timeout | WHEN the aggregate read never answers, THE SYSTEM SHALL time out and allow a retry | a lost reply must not leave the page blank | `F:browse_albums_test#a read that never answers times out and can be retried` |
| ALB-8 | Handoff | WHEN the list is cleared, THE SYSTEM SHALL read again next time | the handoff resets both singletons | `F:browse_albums_test#clear drops the list so a handoff can read it again` |
| ALB-9 | Folder read | WHEN a folder is opened, THE SYSTEM SHALL read that folder alone, whole | a folder's count is already whole | `F:browse_album_loader_test#loads only its own folder and orders it like the timeline`; `F:browse_album_loader_test#reads a folder bigger than one page whole` |
| ALB-10 | Partial failure | WHEN a folder read fails after some rows, THE SYSTEM SHALL keep them and offer a retry | a failed tail must not hide the head | `F:browse_album_loader_test#a read that fails ends loading and leaves the page with an empty album`; `F:browse_album_loader_test#a failed read can be resumed` |
| ALB-11 | Loading signal | WHEN a folder loads, THE SYSTEM SHALL notify while loading and once the rows land | the page must leave its spinner | `F:browse_album_loader_test#notifies the page while it loads and once the rows land` |

## Navigation and drawer

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| BAR-1 | User's bar | WHEN the bar renders, THE SYSTEM SHALL keep the user's items, order and labels and append the visible-range destination once | a fixed bar was tried and reverted | `F:browse_bottom_bar_test#the bar follows the configured order and greys what it cannot serve` |
| BAR-2 | Greyed entries | WHEN an entry needs catalogued metadata, THE SYSTEM SHALL dim it and give it no tap handler | a reactive grey entry would flash a ripple and do nothing | `F:browse_bottom_bar_test#the bar follows the configured order and greys what it cannot serve` |
| DRW-1 | Organized library | WHEN the library is organized, THE SYSTEM SHALL enable every drawer destination | browsing restrictions must end at the handoff | `F:browse_drawer_entry_test#everything is reachable once the library is organized` |
| DRW-2 | Browsable entries | WHILE browsing, THE SYSTEM SHALL enable the timeline, the album list, the explorer and the app pages | these ask the media store, not the database | `F:browse_drawer_entry_test#the whole timeline and the folder list stay reachable while organizing`; `F:browse_drawer_entry_test#the app pages and the file system stay reachable while organizing` |
| DRW-3 | Metadata entries | WHILE browsing, THE SYSTEM SHALL grey anything narrowed by catalogued metadata | a half-built catalogue would answer wrongly | `F:browse_drawer_entry_test#anything narrowed by catalogued metadata is greyed while organizing` |
| DRW-4 | Unknown route | WHILE browsing, THE SYSTEM SHALL grey a destination its whitelist does not name | guessing wrong costs a broken view | `F:browse_drawer_entry_test#a destination the whitelist does not know is greyed` |

## Layout and states

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| UI-1 | Section header | WHEN the timeline scrolls, THE SYSTEM SHALL let the month header scroll away with its rows | a pinned header never shrinks and stacks headers on screen | `F:browse_media_grid_test#the month header scrolls away with the rows under it` |
| UI-2 | Viewer window | WHEN a tile is tapped, THE SYSTEM SHALL open the viewer with a bounded neighbourhood | materializing the whole index would recreate the library | `-:needs a page route and the viewer; see tasks.md` |
| UI-3 | Empty and failed states | WHEN a view is empty or failed, THE SYSTEM SHALL say why and offer the matching action | a blank screen is indistinguishable from a bug | `-:layout, covered by the device checks in testing.md` |
| UI-4 | Preview strip | WHEN the limit is reached or the last page failed, THE SYSTEM SHALL show the preview strip with its action | the user must be able to pass the limit or retry | `-:layout` |

## Preferences

| ID | Case | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- |
| PRF-1 | Persisted sort | WHEN a browse sort is picked, THE SYSTEM SHALL persist it under its own keys | the browser's sort must not move the collection's | `F:browse_prefs_test#persists a picked media sort under its own keys`; `F:browse_prefs_test#persists a picked album sort under its own keys` |
| PRF-2 | Separate namespace | WHEN a sort is persisted, THE SYSTEM SHALL not write the collection's sort settings | the collection must come back unchanged after the handoff | `F:browse_prefs_test#persists a picked media sort under its own keys` |
| PRF-3 | Read fallback | WHEN a preference cannot be read or holds an unknown value, THE SYSTEM SHALL keep the default | a corrupt value must not break the page | `F:browse_prefs_test#starts from the gallery defaults`; `F:browse_prefs_test#keeps the default for a value it cannot read` |
| PRF-4 | No-op pick | WHEN the picked sort equals the current one, THE SYSTEM SHALL neither notify nor write | repicking must not churn the prefs or the grid | `F:browse_prefs_test#picking the current sort neither notifies nor writes` |
| PRF-5 | Read once | WHEN the preferences have loaded, THE SYSTEM SHALL not read them again | a second page mount must not reset a just-picked sort | `F:browse_prefs_test#init reads once and later calls do not re-read` |
| PRF-6 | Both entry points | WHEN either browse view opens, THE SYSTEM SHALL load the preferences | opening Albums first must not show defaults while its sort writes the same keys | `-:the call is in each page's initState; a widget test of both pages is not written (see testing.md)` |
