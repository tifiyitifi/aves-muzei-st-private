# Visible range — what comes back

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | The grid is narrowed but the album counts and covers still describe the whole library | A summary path re-derived the range instead of using the gate's complement | `GAT-1`, `GAT-2`, `GAT-3` | A new browsing path reads the controller directly, or builds `summaryExclusion` itself | implementation, 2026 |
| R2 | The wallpaper page's group range keeps restricting browsing after the page is gone | The overlay was released without its owner token, or a page compared values instead of identity | `GAT-8`, `GAT-9`, `GAT-10`, `SCO-1` | `releaseWallpaperScope` loses the token, or `claimWallpaperScope` stops taking over | implementation, 2026 |
| R3 | A range narrows the recycle bin, so nothing can be restored | The gate applied the range to a trash view | `GAT-4` | The `TrashFilter` exemption is removed while refactoring `apply()` | implementation, 2026 |
| R4 | After a defaults bump the user's own rules disappear | The seed replaced the whole set instead of pruning built-ins | `CTL-10`, `CTL-14` | The seed deletes by range instead of by built-in id | implementation, 2026 |
| R5 | The library opens empty after a restart | A corrupt filter column decoded to an exception, or a broken store hid the range | `STO-1`, `STO-7` | `VisibleRangeFilterCodec.decode` throws, or the controller keeps `_gallery` null | implementation, 2026 |
| R6 | A wallpaper group loses its base when switched off and on again | The base filters were cleared instead of kept with `baseActive` false | `MOD-2`, `MIG-3` | The page writes empty filters when toggling the base off | implementation, 2026 |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | The resolved filter tree | paged predicate, summary exclusion, legacy scan | Change `resolve()` in one place; every path reads the gate | `visible_range.dart`, `visible_range_gate.dart` |
| C2 | `(scope, ownerId)` | store reads and writes, wallpaper groups, gallery | Never load a range without both values | `visible_range_store.dart` |
| C3 | The overlay owner token | every page that publishes or releases a scope | Publish and release only with the token the claim returned | `visible_range_gate.dart` |
| C4 | `defaultsVersion` | bundled asset, seed, built-in rule ids | Bump it when the bundle changes; never renumber built-in ids | `visible_range_store.dart`, `default_presets.dart` |
| C5 | The lock permissions | gate `allows()`, every action mapping | Add a mutation only with its permission and its action mapping | `visible_range_locks.dart` |
