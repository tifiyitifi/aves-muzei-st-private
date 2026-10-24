/*
 * Copyright 2026 Aves contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package deckers.thibault.aves.features.muzei_wallpaper

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * The promotion queue the renderer reads from `state.json`.
 *
 * The deeper spare (`next2`) is what makes the second wallpaper tap instant, so
 * the "slot after the displayed one" rule is pinned here: the renderer derives
 * the promotable spare from it on every load, including reloads that happen
 * mid-crossfade.
 */
class WallpaperFileStateTest {
    private fun state(current: Int, next: Int, next2: Int) = WallpaperFileState(
        generation = 7,
        current = current,
        next = next,
        next2 = next2,
        slots = listOf(0, 1, 2).associateWith { id ->
            WallpaperSlotFiles(
                id = id,
                entryId = 100 + id,
                sharp = "slots/$id/sharp.png",
                effectsHome = "slots/$id/effects_home.png",
                effectsLock = "slots/$id/effects_lock.png",
            )
        },
        doubleTapAction = "nextArtwork",
        threeFingerAction = "none",
    )

    @Test
    fun `a two-ahead state exposes both spares in promotion order`() {
        val state = state(current = 0, next = 1, next2 = 2)

        assertEquals(1, state.promotableAfter(0))
        assertEquals(2, state.promotableAfter(1))
        assertEquals(-1, state.promotableAfter(2), "nothing is baked after the deepest slot")
        assertEquals(-1, state.promotableAfter(9), "unknown slots are never promoted")
    }

    @Test
    fun `a legacy state without next2 still promotes its single spare`() {
        val state = state(current = 0, next = 1, next2 = -1)

        assertEquals(1, state.promotableAfter(0))
        assertEquals(-1, state.promotableAfter(1))
    }

    @Test
    fun `the displayed slot follows a matching runtime and ignores a stale one`() {
        val state = state(current = 0, next = 1, next2 = 2)

        assertEquals(1, state.displaySlot(WallpaperRuntime(generation = 7, current = 1, next = 2))?.id)
        assertEquals(0, state.displaySlot(WallpaperRuntime(generation = 6, current = 1, next = 2))?.id)
        assertEquals(0, state.displaySlot(WallpaperRuntime(generation = 7, current = 9, next = -1))?.id, "an unknown runtime slot falls back to the state")
    }
}
