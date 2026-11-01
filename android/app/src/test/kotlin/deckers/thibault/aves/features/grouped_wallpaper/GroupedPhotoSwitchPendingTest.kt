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
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The bar keeps saying "switching" only while the photo on screen is the one the
 * tap left; a promotion or a re-bake has to end it.
 */
class GroupedPhotoSwitchPendingTest {
    @Test
    fun `the same slot and entry are still the photo the tap left`() {
        assertTrue(GroupedPhotoSwitchPending.isSamePhoto(fromSlotId = 1, fromEntryId = 10, slotId = 1, slotEntryId = 10))
    }

    @Test
    fun `a promoted slot ends the wait`() {
        assertFalse(GroupedPhotoSwitchPending.isSamePhoto(fromSlotId = 1, fromEntryId = 10, slotId = 2, slotEntryId = 20))
    }

    @Test
    fun `a re-baked slot with another entry ends the wait`() {
        assertFalse(GroupedPhotoSwitchPending.isSamePhoto(fromSlotId = 1, fromEntryId = 10, slotId = 1, slotEntryId = 11))
    }

    @Test
    fun `no photo on screen ends the wait`() {
        assertFalse(GroupedPhotoSwitchPending.isSamePhoto(fromSlotId = 1, fromEntryId = 10, slotId = null, slotEntryId = null))
    }

    @Test
    fun `a wait that outlived its deadline ends`() {
        assertFalse(GroupedPhotoSwitchPending.stillWaiting(samePhoto = true, elapsedMs = 20_001, timeoutMs = 20_000))
    }

    @Test
    fun `a wait inside its deadline holds`() {
        assertTrue(GroupedPhotoSwitchPending.stillWaiting(samePhoto = true, elapsedMs = 1_000, timeoutMs = 20_000))
    }
}
