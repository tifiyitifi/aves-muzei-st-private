# Grouped wallpaper — what comes back

`rules.md` says what the feature must do. This file says **how the rule set
fails**: the complaints that return, and the couplings that make fixing one of
them break another.

Two readings:

- **R** — a symptom a user can report. Each one has a mechanism, a rule that now
  holds it, and a condition under which it returns.
- **C** — a coupling: one input read by several subsystems, so a change aimed at
  one of them lands in all of them.

A change is not finished until it says which R it is about and which C it
touches. `decisions/` records the ones that needed a judgement, not a fix.

## R — the complaints that return

| ID | Symptom | Mechanism | Held by | Comes back if | Source |
| --- | --- | --- | --- | --- | --- |
| R1 | The view page shows one photo while the wallpaper shows another | A reader resolved a slot id against `state.json`, but the renderer had promoted a slot on its own, kept an older generation, or the file was already newer | `DISP-1` … `DISP-6`, `C1` | Any surface reads `state.current` or `state.slotById(displayedSlot)` without the renderer's generation | `b70fe105c`, `cfd6c25d2`, `83a03140d` |
| R1b | Consecutive steps stop updating the page (1→2 works, 3→4 do not) | Same as R1, reached when the refill wrote `G+1` before the renderer adopted it: the promoted id in `G` named a different photo in `G+1` | `DISP-3`, `DISP-4`, `C1` | The displayed slot is still an id without its generation | device report, 2026; fixed by the displayed-slot snapshot ([0001](decisions/0001-a-slot-id-is-only-valid-in-its-generation.md)) |
| R2 | Returning to the home screen shows the grey placeholder or the previous photo | A surface rebuild cleared every texture, or a reload judged a frame stale because this reload did not decode it | `RET-1` … `RET-3`, `C2`, `C6` | `onSurfaceCreated` clears uploaded frames, or retention reads the decoded set | `3eadeada2`, `4c9d005d1`, `83a03140d` |
| R3 | A tap does nothing, or a second tap is lost | The gesture relied on a launcher command, a tap during a bake was dropped, or two paths claimed the same tap | `PROM-1` … `PROM-3`, `C3` | The tap buffer is removed, or "waiting" and "must not move" collapse into one answer | `56393f4ef`, `2da262cf3`, `a7d07c57d` |
| R4 | The wallpaper never turns a landscape photo, or the image fit is wrong | `WallpaperManager` reported a square desired size; the launcher's step was read from the preview engine or carried across a launcher change | `SIZE-1`, `SIZE-2`, `C4` | A bake sizes from the manager hint, or the measurement outlives its launcher | `3fb31e417`, `9f493f8e2` |
| R5 | The wallpaper disappears after an app update or a force-stop | An OEM resets the live component instead of rebinding it, and MIUI silences the app's notifications | `RSTR-1`, `RSTR-2`, `C5` | The restore check is removed, or a silent rebind is attempted | `643b992fc`, `de0aa5173` |
| R6 | The notification bar stays after the wallpaper is gone | `onDestroy` cleared the bar, then `super.onDestroy()` posted it again; a service the OEM killed never ran `onDestroy` | `-:native GroupedWallpaperNotification` | The `destroying` flag is dropped, or the attach-time cancel is removed | `c98076253`, `77630765a` |
| R7 | Leaving an app to the home screen first shows the wallpaper from the previously set Muzei, then this one | The system keeps the replaced wallpaper as its previous one and may draw it while the new engine starts; an OEM that kills the engine makes the window reappear on every return | `SWITCH-1`, `C5` | The engine is killed and rebound often; this is a system transition, not an app state | device report, 2026; [0002](decisions/0002-the-previous-wallpaper-flash-is-the-system.md) |

## C — the couplings

| ID | Shared input | Readers | Safe change | Source |
| --- | --- | --- | --- | --- |
| C1 | A slot id | queue, display, notification, effects editor, `runtime.json` | Treat an id as valid only inside the generation that produced it; carry the renderer's generation (or its slot snapshot) with the id | `b70fe105c`, `cfd6c25d2`, `83a03140d` |
| C2 | `state.json` generation | baker, reload, retention, runtime adoption | Bump once per write; discard a reload older than the drawn state; never rewrite the generation for a setting-only change | `83a03140d`, `3ed35fb77` |
| C3 | The request-serving predicate | native service, background worker, app handler | One predicate (`messenger` and attached handler) decides; never let the two sides answer differently | `a7d07c57d` |
| C4 | `surfaceSize` / `scrollStep` | baker, renderer, capability warning, framing | Record from the real engine only; drop on a launcher change; keep the manager hint as the last resort | `3fb31e417`, `9f493f8e2`, `0f3035214` |
| C5 | The wallpaper component | two services, `isActive`, `restoreOffer`, notification, chooser | Setting one live wallpaper replaces the other; the system keeps the replaced one as its previous wallpaper, so the app must never assume it owns the transition | `23c6131aa`, `643b992fc`, `c98076253` |
| C6 | The frame cache key `(entryId, photo)` | loader skip, retention, bake, texture upload | Keep the key in one place; retention follows the new state, not the decoded set | `3eadeada2`, `83a03140d` |
