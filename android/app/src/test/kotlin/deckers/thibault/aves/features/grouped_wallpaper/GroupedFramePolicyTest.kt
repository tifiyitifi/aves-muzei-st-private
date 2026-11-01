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

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The retention switch trades GPU memory for an instant tap; the frame on screen
 * must survive every setting, and a limited reload must still decode what the
 * user is waiting for.
 */
class GroupedFramePolicyTest {
    @Test
    fun `an unknown or missing name falls back to keeping every frame`() {
        assertEquals(GroupedFrameRetention.ALL, GroupedFrameRetention.parse(null))
        assertEquals(GroupedFrameRetention.ALL, GroupedFrameRetention.parse(""))
        assertEquals(GroupedFrameRetention.ALL, GroupedFrameRetention.parse("nonsense"))
        assertEquals(GroupedFrameRetention.DISPLAYED, GroupedFrameRetention.parse("displayed"))
        assertEquals(GroupedFrameRetention.AUTO, GroupedFrameRetention.parse("AUTO"))
    }

    @Test
    fun `auto only limits the layout with wide frames`() {
        assertFalse(GroupedFrameRetention.AUTO.limitsNeighbours(scrollEffect = false))
        assertTrue(GroupedFrameRetention.AUTO.limitsNeighbours(scrollEffect = true))
        assertFalse(GroupedFrameRetention.ALL.limitsNeighbours(scrollEffect = true))
        assertTrue(GroupedFrameRetention.DISPLAYED.limitsNeighbours(scrollEffect = false))
    }

    @Test
    fun `an unlimited reload decodes every queued slot in order`() {
        assertEquals(listOf(0, 1, 2), GroupedFramePolicy.decodeOrder(listOf(0, 1, 2), listOf(1), limitNeighbours = false))
    }

    @Test
    fun `a limited reload decodes the wanted frames in order`() {
        assertEquals(listOf(1), GroupedFramePolicy.decodeOrder(listOf(0, 1, 2), listOf(1), limitNeighbours = true))
        // A buffered tap adds its target behind the frame on screen.
        assertEquals(listOf(1, 2), GroupedFramePolicy.decodeOrder(listOf(0, 1, 2), listOf(1, 2), limitNeighbours = true))
        // A want that the state no longer queues decodes nothing.
        assertEquals(emptyList<Int>(), GroupedFramePolicy.decodeOrder(listOf(0, 1), listOf(9), limitNeighbours = true))
    }

    @Test
    fun `a limited reload keeps only the frame about to be shown`() {
        assertEquals(
            setOf(1),
            GroupedFramePolicy.retainedIds(slots = setOf(0, 1, 2), intent = 1, limitNeighbours = true, drawable = setOf(0, 1, 2)),
        )
    }

    @Test
    fun `a limited reload steps aside while its frame is not drawable`() {
        // The wanted frame failed to decode: a neighbour is the only alternative
        // to the placeholder, so nothing is evicted.
        assertEquals(
            setOf(0, 1, 2),
            GroupedFramePolicy.retainedIds(slots = setOf(0, 1, 2), intent = 1, limitNeighbours = true, drawable = setOf(0, 2)),
        )
    }

    @Test
    fun `an unlimited reload keeps every slot the state names`() {
        assertEquals(
            setOf(0, 1, 2),
            GroupedFramePolicy.retainedIds(slots = setOf(0, 1, 2), intent = 1, limitNeighbours = false, drawable = setOf(1)),
        )
    }
}
