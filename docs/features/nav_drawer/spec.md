# Navigation drawer pages — spec

Requirements are written with EARS: `WHEN <trigger>, THE SYSTEM SHALL <response>`.
One observable behaviour per sentence.

### FR-1 — The drawer pages are one ordered list

WHEN the drawer opens, THE SYSTEM SHALL render exactly the page entries of
`drawer_page_bookmarks`, in their stored order, and SHALL NOT inject a page the
list does not name.

Rules: `DRW-2`, `DRW-3`.

### FR-2 — The fork pages are editor options

WHEN the drawer editor's Pages tab opens, THE SYSTEM SHALL offer the visible
range, the Muzei Wallpaper page and the wallpaper groups after the upstream page
options, and SHALL offer each route once.

Rules: `DRW-3`.

### FR-3 — Defaults

WHEN the list has never been saved, THE SYSTEM SHALL show the visible range in
the slot the fixed tile had, and SHALL NOT show the Muzei Wallpaper page or the
wallpaper groups.

Rules: `DRW-1`, `DRW-2`.

### FR-4 — A legacy list keeps the visible range

WHEN a page list was saved before the fork pages became editable, THE SYSTEM
SHALL insert the visible range before Explorer, or last when the list has no
Explorer, and SHALL do it once.

Rules: `DRW-5`, `DRW-6`, `DRW-7`, `DRW-8`.

### FR-5 — A pick leaves the fork pages out

WHEN a photo is being picked, THE SYSTEM SHALL omit the fork pages from the
drawer and SHALL keep every other entry in place.

Rules: `DRW-4`.

### FR-6 — The wallpaper-groups entry opens the range's wallpaper page

WHEN the user opens the wallpaper groups from the drawer, THE SYSTEM SHALL open
the same destination as the visible range's「Open wallpaper groups」action.

Rules: `NAV-3` in the grouped-wallpaper register.
