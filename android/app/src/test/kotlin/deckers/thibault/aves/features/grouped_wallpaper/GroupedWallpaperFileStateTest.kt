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

package deckers.thibault.aves.features.grouped_wallpaper

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * What the renderer and the bar may offer, from `state.json` alone.
 *
 * The range lock protects editing and browsing, not the photos: a legacy
 * `locked` state must still step forward and back exactly like a `ready` one.
 */
class GroupedWallpaperFileStateTest {
    private fun state(
        status: String,
        count: Int = 3,
        previous: Int = -1,
        next: Int = -1,
        canPrevious: Boolean = true,
    ) = GroupedWallpaperFileState(
        generation = 1,
        status = status,
        groupId = "group.1",
        groupNumber = 1,
        groupName = "DCIM",
        count = count,
        current = 0,
        previous = previous,
        next = next,
        slots = emptyList(),
        doubleTap = GroupedWallpaperFileState.ACTION_NEXT_ARTWORK,
        threeFinger = GroupedWallpaperFileState.ACTION_VIEW_ARTWORK,
        canPrevious = canPrevious,
    )

    @Test
    fun `a ready state promotes the queued next slot`() {
        assertTrue(state(GroupedWallpaperFileState.STATUS_READY, next = 1).canPromote)
    }

    @Test
    fun `a legacy locked state still promotes the queued next slot`() {
        assertTrue(state(GroupedWallpaperFileState.STATUS_LOCKED, next = 1).canPromote)
    }

    @Test
    fun `an empty group keeps the slot the previous group baked`() {
        // Dart records the empty group without clearing its slots, so the bar and
        // a restarted renderer still have the frame the wallpaper is showing.
        val kept = state(GroupedWallpaperFileState.STATUS_EMPTY_GROUP, count = 0).copy(
            slots = listOf(GroupedWallpaperSlotFile(id = 0, entryId = 1, photo = "slots/0.png")),
        )
        assertNotNull(kept.currentSlot)
        assertFalse(kept.canPromote)
    }

    @Test
    fun `a turned-off state promotes nothing`() {
        assertFalse(state(GroupedWallpaperFileState.STATUS_DISABLED, next = 1).canPromote)
    }

    @Test
    fun `a single photo group never moves`() {
        assertFalse(state(GroupedWallpaperFileState.STATUS_READY, count = 1, previous = 1, next = 2).canPromote)
        assertFalse(state(GroupedWallpaperFileState.STATUS_READY, count = 1, previous = 1, next = 2).canRegress)
    }

    @Test
    fun `a ready state steps back when a recorded previous is queued`() {
        assertTrue(state(GroupedWallpaperFileState.STATUS_READY, previous = 1).canRegress)
    }

    @Test
    fun `a legacy locked state still steps back`() {
        assertTrue(state(GroupedWallpaperFileState.STATUS_LOCKED, previous = 1).canRegress)
    }

    @Test
    fun `stepping back needs recording to be on`() {
        assertFalse(state(GroupedWallpaperFileState.STATUS_READY, previous = 1, canPrevious = false).canRegress)
    }

    @Test
    fun `stepping back needs a queued previous slot`() {
        assertFalse(state(GroupedWallpaperFileState.STATUS_READY, previous = -1).canRegress)
    }

    @Test
    fun `a turned-off state steps back to nothing`() {
        assertFalse(state(GroupedWallpaperFileState.STATUS_DISABLED, previous = 1).canRegress)
    }
}
