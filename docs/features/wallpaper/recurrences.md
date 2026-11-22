# Wallpaper family — what comes back

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | The page names one photo while the wallpaper shows another | A reader resolved a slot id against `state.json` while the renderer had promoted a slot in another generation | `STA-7`, `CTL-5` | A surface reads `state.current` without the runtime's generation | `grouped_wallpaper` R1, same mechanism |
| R2 | A tap is lost, or the wallpaper jumps back to the previous photo | A bake committed `current` after a tap had promoted the spare | `CTL-2`, `CTL-12` | The commit writes `current` from a snapshot taken before the advance | implementation, 2026 |
| R3 | The wallpaper stops advancing after the app is closed | The callback handle was not re-registered, or the worker never heard `initialized` | `REF-1`, `REF-4` | Registration is moved out of every app start, or `initialized` is awaited after the handler | implementation, 2026 |
| R4 | Choosing a new interval does not change the running schedule | The option was added to the list without fanning out to the selections | `AUT-5` | A catalog action stops calling the selection-reset seam | `wallpaper_auto_advance` README |
| R5 | A deleted interval keeps firing, or deleting one resets everything | Deletion reset every selection instead of only the users of that value | `AUT-5` | The reset iterates the whole catalog instead of the removed value | implementation, 2026 |
| R6 | The lock is on but the group can still be left | The group lock was stored per page instead of in `appMeta`, or the service was not loaded before the page | `LCK-3`, `LCK-6` | The lock state moves into the page, or init is deferred | implementation, 2026 |
| R7 | A single picture disappears when its original is deleted | The private copy was treated as a cache and pruned | `SRC-13`, `SG-1`, `SG-2` | Cleanup deletes the `source/` directory or the copy is tied to the library row | implementation, 2026 |
| R8 | The preview and the desktop look different | The preview re-implemented the cover or effect maths | `BAK-2`, `COV-1`, `APR-3` | A preview path stops sharing the bake's formula | implementation, 2026 |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | A slot id and its generation | page, renderer, `runtime.json`, notification | Treat an id as valid only in its generation; carry the runtime generation with it | `wallpaper_state.dart` |
| C2 | `state.json` / `runtime.json` | Dart baker, native renderer, background refill | Write atomically under the file lock; never write `current` from a stale snapshot | `wallpaper_state_store.dart`, native renderer |
| C3 | The interval option list | both wallpapers' selections, the editor, the schedule | Change it only through the controller, and fan out through the reset seam | `wallpaper_interval_options_controller.dart` |
| C4 | A PIN per lock kind | lock service, range unlock, group switch | Keep one key per kind; never share a PIN between them | `wallpaper_lock_service.dart` |
| C5 | The refill callback handle | native worker, app start | Re-register at every start; the handle is part of the AOT snapshot | `refill_entry.dart` |
| C6 | The effect and framing config | preview, baker, desktop | Read the same value object; clamp on read | `wallpaper_effects.dart` |
