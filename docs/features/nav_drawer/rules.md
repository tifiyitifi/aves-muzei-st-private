# Navigation drawer pages — rule register

One row per case the feature has to get right. A behaviour that is not listed
here is a side effect nobody has named yet.

Columns:

- **Case** — the situation, in one line.
- **Evidence** — what the row has to show for the behaviour to be allowed.
- **Behaviour** — what the feature must do.
- **Why** — the reason the row exists. No real path or title.
- **Coverage** — `;`-separated tokens:
  - `F:<test file stem>#<test name>` — resolved by
    `scripts/check-nav-drawer-rules.ps1`.
  - `M` — needs a human on a device; the step is in `testing.md`.
  - `-:<reason>` — deliberately unfalsified.

A rule that stops being true is **superseded**, not deleted.

## Entries

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| DRW-1 | Defaults | The list has never been saved | WHEN the drawer opens on a fresh install, THE SYSTEM SHALL show the visible range and SHALL NOT show Muzei Wallpaper or the wallpaper groups | the first two used to be fixed tiles; only the range was visible | `F:drawer_page_routes_test#a fresh install shows the visible range but neither wallpaper page` |
| DRW-2 | Legacy slot | The range used to sit before Explorer | WHEN the visible range is in the list, THE SYSTEM SHALL render it where the list places it | the fixed tile sat immediately before Explorer, so the default keeps that order | `F:drawer_page_routes_test#the visible range keeps the slot the fixed tile had` |
| DRW-3 | Editor options | The fork pages write wallpaper state | WHEN the Pages tab opens, THE SYSTEM SHALL offer the upstream options first, then the fork pages, each once | the fork destinations belong where the user manages the drawer | `F:drawer_page_routes_test#the editor offers the fork pages after the upstream ones`; `F:drawer_page_routes_test#a fork page already offered upstream is not offered twice` |
| DRW-4 | Picking | A pick owns the wallpaper state | WHEN a photo is being picked, THE SYSTEM SHALL omit the fork pages and keep every other entry in place | a fork page opened from the picker is a second writer for the same state | `F:drawer_page_routes_test#a pick drops the fork pages and keeps every other page in place` |

## Backfill

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| DRW-5 | A legacy list | A saved list lacks the range | WHEN a list saved before the fork pages became editable is found, THE SYSTEM SHALL insert the visible range before Explorer, or last when there is no Explorer | upgrading must not silently remove an entry the user could not have removed | `F:drawer_page_seed_test#a list saved before the fork pages became editable gets the visible range back`; `F:drawer_page_seed_test#goes before Explorer`; `F:drawer_page_seed_test#goes last when the list has no Explorer` |
| DRW-6 | One-time | An editor save records a decision | WHEN the drawer editor saves, THE SYSTEM SHALL record that the list was seen, and THE SYSTEM SHALL NOT backfill again | a later removal is the user's decision, not an un-migrated list | `F:drawer_page_seed_test#a list the editor already saved is a decision and stays alone` |
| DRW-7 | TV | The rail writes its own list | WHEN the device uses the TV layout, THE SYSTEM SHALL leave the list untouched | the fixed drawer tile never existed on the rail | `F:drawer_page_seed_test#the TV rail keeps its own list` |
| DRW-8 | Fresh install | The defaults already carry the range | WHEN the list has never been saved, THE SYSTEM SHALL NOT write a list just to add the entry | pinning the defaults would freeze them for future changes | `F:drawer_page_seed_test#a fresh install keeps the defaults and is only marked` |
