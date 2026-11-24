# Grouped wallpaper — rule register

One row per case the feature has to get right. A behaviour that is not listed
here is a side effect nobody has named yet.

Columns:

- **Case** — the situation, in one line.
- **Evidence** — what the row has to show for the behaviour to be allowed.
- **Behaviour** — what the feature must do. Normative; `design.md` holds the
  invariants behind it.
- **Why** — the commit that made this a rule, then the sentence. No real path,
  title or account name.
- **Coverage** — `;`-separated tokens in one cell:
  - `F:<test file stem>#<test name>` — a Dart test with exactly that name exists
    and fails when the rule breaks. `scripts/check-grouped-wallpaper-rules.ps1`
    resolves every token.
  - `-:native <test class>` — a Kotlin host test holds the rule.
  - `M` — needs a human on a device; the step is in `testing.md`.
  - `-:<reason>` — deliberately unfalsified.

A rule that stops being true is **superseded**, not deleted: keep the row, mark
it `superseded by <ID>` and leave the coverage that used to hold it.

## Display

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| DISP-1 | The renderer promoted a neighbour | The renderer draws `next` while `state.json` still says `current` | WHEN the view page describes a home photo, THE SYSTEM SHALL describe the slot the renderer draws | `b70fe105c`, `cfd6c25d2`: the app described a photo the user was not looking at | `F:grouped_wallpaper_engine_test#describes the slot the engine draws, not the baked current` |
| DISP-2 | A view-page step promotes | The promotion writes `runtime.json` before the bake | WHEN a home step promotes, THE SYSTEM SHALL describe the promoted slot without waiting for the refill | `409366823`: a step is a texture swap and the page can name it at once | `F:grouped_wallpaper_engine_test#a promotion is described before the refill` |
| DISP-3 | Several steps before the refill writes | Consecutive steps each promote a queued slot | WHEN the user steps more than once before the next state is written, THE SYSTEM SHALL describe the drawn slot after every step | `b70fe105c`, `83a03140d`: the drift returned whenever a reader resolved the id against a newer file | `F:grouped_wallpaper_state_test#consecutive steps keep describing the drawn slot` |
| DISP-4 | Renderer and file disagree on generation | The renderer draws generation `G`, the file is `G+1` | WHEN the generations differ, THE SYSTEM SHALL use the renderer's own slot metadata and SHALL NOT resolve the id against the newer file | `b70fe105c`, `cfd6c25d2`: a slot id is only valid in its generation | `F:grouped_wallpaper_state_test#a slot id is resolved in the renderer generation, not the newer file` |
| DISP-5 | No renderer is attached | Nothing is drawing the wallpaper | WHEN no renderer runs, THE SYSTEM SHALL fall back to the baked `current` | `b70fe105c`: a stale answer beats none | `F:grouped_wallpaper_engine_test#falls back to the baked current when no engine runs` |
| DISP-6 | The drawn slot was pruned | The renderer kept a slot the new state no longer queues | WHEN the drawn slot is missing from the state, THE SYSTEM SHALL fall back to the baked `current` | `b70fe105c`: a promoted slot can be pruned by a later reload | `F:grouped_wallpaper_engine_test#falls back when the drawn slot was pruned` |
| DISP-7 | The surface is the lock | The group splits its surfaces | WHEN the lock surface is described, THE SYSTEM SHALL describe the state's decoy frame, not a queue slot | `035a0b10c`, `58f152778`: the decoy is not a queue slot | `F:grouped_wallpaper_engine_test#describes the effect image of the surface on screen` |
| DISP-8 | A step had to bake | The renderer still draws the frame the step replaced | WHEN a step falls back to a bake, THE SYSTEM SHALL describe the baked current immediately and SHALL NOT wait for the renderer to reload | device report, 2026: the page stayed on the old photo or the empty placeholder while the desktop changed | `F:grouped_wallpaper_engine_test#after a bake, describes the baked current, not the renderer behind it` |
| DISP-9 | The drawn frame is gone | The renderer names a slot whose frame the cache evicted | WHEN the selected slot has no file, THE SYSTEM SHALL fall back to the baked current instead of the placeholder | device report, 2026: a stale slot's missing frame left the page empty | `F:grouped_wallpaper_engine_test#a drawn frame whose file was evicted falls back to the baked current` |

## Promotion and taps

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| PROM-1 | A promotable tap | The next slot's texture is uploaded | WHEN a tap can promote, THE SYSTEM SHALL promote the queued neighbour and SHALL NOT also bake | `760439753`, `409366823`: a tap is one texture swap | `F:grouped_wallpaper_engine_test#a promotion swaps the queued neighbour and refills in the background` |
| PROM-2 | A tap before the upload | The next slot is still baking | WHEN a tap arrives before the neighbour is uploaded, THE SYSTEM SHALL buffer it and replay it after the refill | `56393f4ef`, `2da262cf3`: a late command used to lose the tap | `-:native GroupedAdvanceRequestQueueTest` |
| PROM-3 | A wallpaper that must not move | The group is turned off or is group 0 | WHEN the wallpaper must not move, THE SYSTEM SHALL NOT buffer the tap | `2da262cf3`: a request buffered across an off switch fires long after the user tapped | `-:native GroupedTapGateTest` |

## Reload and retention

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| RET-1 | A reload settles the drawn slot | The state's current has no texture yet | WHEN a reload runs, THE SYSTEM SHALL keep the slot on screen and make the fallback reversible | `83a03140d`, `4c9d005d1`: a fallback that never comes back left the previous photo for good | `-:native GroupedDisplayTest` |
| RET-2 | A reload decides which frames to drop | A frame is on the GPU but this reload did not decode it | WHEN a reload keeps a slot, THE SYSTEM SHALL keep its uploaded texture | `3eadeada2`: judging by the decoded set deleted every neighbour | `-:native GroupedTextureRetentionTest` |
| RET-3 | An older state arrives | A reload raced a writer | WHEN a loaded state is older than the one on screen, THE SYSTEM SHALL discard it | `83a03140d`: retention would treat the newer slots as garbage | `-:native GroupedDisplayTest` |

## Sizing

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| SIZE-1 | The frame size | The renderer measured its surface | WHEN a frame is baked, THE SYSTEM SHALL size it from the real renderer surface, not from `WallpaperManager`'s desired size | `3fb31e417`: MIUI reported a square canvas and no photo was ever turned | `F:grouped_wallpaper_engine_test#bakes the photo's whole width at the surface height` |
| SIZE-2 | The launcher changed | The step and offset belong to the previous launcher | WHEN the resolved launcher differs, THE SYSTEM SHALL drop the previous measurement | `9f493f8e2`: a phone that once panned never narrowed again | `F:grouped_wallpaper_engine_test#a launcher that stops panning narrows once and stays narrow` |

## Restore

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| RSTR-1 | The wallpaper is gone | The platform says the component is not ours and no other wallpaper was picked | WHEN the loss is real, THE SYSTEM SHALL offer one tap to re-apply | `643b992fc`, `de0aa5173`: an OEM reset is not a user choice | `F:grouped_wallpaper_restore_notice_test#offers nothing until the platform says the wallpaper is gone` |
| RSTR-2 | The user accepts | The offer is tapped | WHEN the user accepts, THE SYSTEM SHALL open the system picker and SHALL NOT rebind silently | `643b992fc`: `SET_WALLPAPER_COMPONENT` is `signature\|privileged` | `F:grouped_wallpaper_restore_notice_test#re-applying opens the system picker` |

## System transition

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| SWITCH-1 | The system rebinds the wallpaper | The engine was destroyed and the system kept the replaced wallpaper | WHEN the system rebinds, THE SYSTEM MAY draw the previous wallpaper until the new engine draws; the app SHALL document this and SHALL NOT claim to remove it | system `WallpaperManagerService` keeps the previous component; observed on MIUI after the engine was killed | `M` |

## Ordering

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| ORD-1 | A group starts its first walk | No state for the group exists yet | WHEN a group starts playing, THE SYSTEM SHALL seed the new-photo marker from the group's id high-water before the first pick | starting at zero made the whole library look new and play in id order | `F:grouped_wallpaper_engine_test#the new-photo marker is seeded from the group before the first pick` |
| ORD-2 | The same group starts over | The current photo left the range | WHEN the same group restarts its walk, THE SYSTEM SHALL keep the marker instead of re-seeding it | a fresh marker would swallow new photos still queued for this group | `F:grouped_wallpaper_engine_test#a same-group restart keeps the seeded marker` |
| ORD-3 | The playing group changes | The plan now names another group | WHEN a different group starts playing, THE SYSTEM SHALL seed a fresh marker from that group | "new" is relative to when the group started playing | `F:grouped_wallpaper_engine_test#switching group seeds a fresh marker from the new group` |
| ORD-4 | A split lock surface starts | The decoy has no frame yet | WHEN the decoy starts picking, THE SYSTEM SHALL seed its marker from the lock range and persist it on the frame | the decoy is its own source and must not walk the whole range in id order | `F:grouped_wallpaper_engine_test#the decoy seeds its new-photo marker from the lock range` |
| ORD-5 | The lock range changes | The split surface points at another range | WHEN the lock range changes, THE SYSTEM SHALL re-seed the decoy's marker from the new range | the previous range's high-water says nothing about the new source | `F:grouped_wallpaper_engine_test#the decoy re-seeds its marker when its range changes` |
| ORD-6 | An old state carries an unseeded home marker | The state predates seeding and holds a photo id | WHEN the next new photo is picked, THE SYSTEM SHALL re-seed the home marker from the group before picking and persist it as seeded | a last-shown id makes "new then random" play the whole library in order | `F:grouped_wallpaper_engine_test#a marker that was never seeded is re-seeded before the next new photo` |
| ORD-7 | The ordering changes while a group plays | The plan names another ordering; `updatedAt` did not move | WHEN the ordering changes, THE SYSTEM SHALL re-seed both surfaces' markers and SHALL keep the photo on screen | ordering edits only change future picks, so no frame is re-baked, but the old marker belongs to the previous strategy | `F:grouped_wallpaper_engine_test#changing the ordering re-seeds the marker without re-baking the photo` |
| ORD-8 | An old decoy carries an unseeded marker | The split frame predates seeding | WHEN the decoy advances, THE SYSTEM SHALL re-seed its marker from the lock range and persist it as seeded on the frame | the decoy is its own source and must not walk its range in id order | `F:grouped_wallpaper_engine_test#the decoy re-seeds a marker left by a build that did not seed it` |
| ORD-9 | The seeded flag crosses a restart | A state with a seeded marker is written and read back | WHEN the state is parsed, THE SYSTEM SHALL read the seeded flag and SHALL read an older file without it as unseeded | the engine must distinguish a seeded high-water from a stale photo id after an app restart | `F:grouped_wallpaper_state_test#a marker seeded for the current group survives the state round-trip`; `F:grouped_wallpaper_state_test#a state written before seeding reads as unseeded` |

## Navigation

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| NAV-1 | A gesture or notification opens the view | The view is the entry page of a cold-start intent | WHEN a gesture or notification opens the view, THE SYSTEM SHALL make it the app's root route and SHALL leave to the desktop on back, honouring the double-back setting | a gesture comes from the desktop; returning there is where the user came from | `M` |
| NAV-2 | The view asks for the group page | The group page is or is not below the view | WHEN the view is the root of its flow, 「Open wallpaper groups」 SHALL push the group page over it; WHEN the group page is already below, it SHALL pop back to it | a gesture-opened view has no page below it, while the group page's menu opens the view from itself | `F:grouped_wallpaper_view_actions_test#a gesture- or notification-opened view pushes the group page`; `F:grouped_wallpaper_view_actions_test#a view opened from the group page goes back` |
| NAV-3 | The drawer asks for the group page | The drawer entry and the range's menu are two ways to the same destination | WHEN the wallpaper groups are opened from the drawer, THE SYSTEM SHALL open the destination the visible range's 「Open wallpaper groups」action opens: the page itself with a separate entry, and the single shared entry on the wallpaper page in the shared mode | two ways to one page must not disagree about the shared navigation mode | `F:grouped_wallpaper_nav_test#the shared entry on screen only flips its sub-page`; `F:grouped_wallpaper_nav_test#a shared entry the user is not on is opened on the wallpaper page`; `F:grouped_wallpaper_nav_test#a separate entry opens the wallpaper page itself`; `M` |

## Destinations

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| DEST-1 | The photo is opened in the viewer | The menu names the viewer, not the album it used to name | WHEN 「Open in viewer」 is chosen, THE SYSTEM SHALL open the app's viewer on the photo on screen | the old label said album while the action already opened the viewer | `M` |
| DEST-2 | The photo's album is opened | The group's conditions are path filters | WHEN 「Open in album」 is chosen, THE SYSTEM SHALL open the stored album that contains the photo, SHALL NOT use a path condition, and SHALL reveal the photo in it | a path condition covers a folder tree, while the album is the one shelf the photo is filed under | `F:grouped_wallpaper_view_actions_test#the album target is the photo's stored album and locates it`; `F:grouped_wallpaper_view_actions_test#the album target needs a directory` |
| DEST-3 | The whole group is opened | The view shows one photo of the group | WHEN 「View whole group」 is chosen, THE SYSTEM SHALL open the group's media set and SHALL reveal the photo on screen in it | the user came from that photo, not from the top of the list | `F:grouped_wallpaper_view_actions_test#the whole group target is the group media set and locates the photo` |

## The group's source union

| ID | Case | Evidence | Behaviour | Why | Coverage |
| --- | --- | --- | --- | --- | --- |
| POOL-1 | A base tap | The base section is a union, one tile per source | WHEN a source base tile is tapped, THE SYSTEM SHALL toggle only that source's mark on the lamped surface; `「All images」` SHALL clear that surface's marks and keep the sources in the pool | treating the base as one unit made several sources impossible to keep on together | `F:wallpaper_group_range_controller_test#each source is marked independently on a surface`; `F:wallpaper_base_tap_test#a source tile toggles only its own mark` |
| POOL-4 | Base header count | The wallpaper pool and the group editor share one header | WHEN the pool's base header is titled, THE SYSTEM SHALL count the sources marked on the lamped surface over all its sources, and SHALL show no count when the pool has none; `「All images」` SHALL NOT be counted | the two surfaces that edit the same union must read the same way | `F:wallpaper_group_sections_test#the base header counts the sources marked on the lamped surface`; `F:wallpaper_group_sections_test#an empty base has no count while its All images tile stays` |

