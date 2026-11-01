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
 * A fallback that never comes back is what makes a surface rebuild show the
 * previous photo for good, so the whole decision table is pinned down here.
 */
class GroupedDisplayTest {
    private fun decide(
        stateCurrent: Int,
        statePrevious: Int = -1,
        stateNext: Int = -1,
        displayed: Int = -1,
        desired: Int = -1,
        fallback: Boolean = false,
        fresh: Boolean = true,
        drawable: Set<Int> = emptySet(),
    ) = GroupedDisplay.decide(
        stateCurrent = stateCurrent,
        statePrevious = statePrevious,
        stateNext = stateNext,
        displayed = displayed,
        desired = desired,
        fallback = fallback,
        fresh = fresh,
        drawable = drawable,
    )

    @Test
    fun `fresh state draws the new current when it is drawable`() {
        val decision = decide(stateCurrent = 1, statePrevious = 2, stateNext = 0, drawable = setOf(0, 1, 2))
        assertEquals(1, decision.displayed)
        assertEquals(1, decision.desired)
        assertFalse(decision.fallback)
        assertFalse(decision.retry)
    }

    @Test
    fun `a fresh state whose current is not drawable keeps the old frame`() {
        val decision = decide(
            stateCurrent = 1,
            statePrevious = 2,
            stateNext = 0,
            displayed = 0,
            drawable = setOf(0, 2),
        )
        assertEquals(0, decision.displayed)
        assertEquals(1, decision.desired)
        assertTrue(decision.fallback)
        assertTrue(decision.retry)
    }

    @Test
    fun `a surface rebuild falls back to a neighbour when the current texture is missing`() {
        // The logged sequence: current is 1, only 0 and 2 were uploaded.
        val decision = decide(
            stateCurrent = 1,
            statePrevious = 2,
            stateNext = 0,
            displayed = 1,
            desired = 1,
            fresh = false,
            drawable = setOf(0, 2),
        )
        assertEquals(2, decision.displayed)
        assertEquals(1, decision.desired)
        assertTrue(decision.fallback)
        assertTrue(decision.retry)
    }

    @Test
    fun `a fallback restores the current once its texture arrives`() {
        val decision = decide(
            stateCurrent = 1,
            statePrevious = 2,
            stateNext = 0,
            displayed = 2,
            desired = 1,
            fallback = true,
            fresh = false,
            drawable = setOf(1, 2),
        )
        assertEquals(1, decision.displayed)
        assertEquals(1, decision.desired)
        assertFalse(decision.fallback)
        assertFalse(decision.retry)
    }

    @Test
    fun `a local promotion survives an unchanged state`() {
        val decision = decide(
            stateCurrent = 2,
            statePrevious = 1,
            stateNext = 0,
            displayed = 1,
            desired = 1,
            fresh = false,
            drawable = setOf(0, 1, 2),
        )
        assertEquals(1, decision.displayed)
        assertFalse(decision.fallback)
    }

    @Test
    fun `an unchanged state does not retry a drawable current`() {
        val decision = decide(
            stateCurrent = 1,
            statePrevious = 2,
            stateNext = 0,
            displayed = 1,
            desired = 1,
            fresh = false,
            drawable = setOf(0, 1, 2),
        )
        assertFalse(decision.retry)
    }

    @Test
    fun `nothing drawable falls back to the placeholder`() {
        val decision = decide(stateCurrent = 1, statePrevious = 2, stateNext = 0, displayed = 1)
        assertEquals(-1, decision.displayed)
        assertFalse(decision.fallback)
        assertTrue(decision.retry)
    }

    @Test
    fun `a single candidate is picked when current and previous are gone`() {
        val decision = decide(
            stateCurrent = 0,
            statePrevious = 1,
            stateNext = 2,
            displayed = -1,
            drawable = setOf(2),
        )
        assertEquals(2, decision.displayed)
        assertTrue(decision.fallback)
        assertTrue(decision.retry)
    }

    @Test
    fun `a stale generation is rejected`() {
        assertTrue(GroupedDisplay.isStaleGeneration(loaded = 151, known = 152))
        assertFalse(GroupedDisplay.isStaleGeneration(loaded = 152, known = 152))
        assertFalse(GroupedDisplay.isStaleGeneration(loaded = 153, known = 152))
    }

    @Test
    fun `the current epoch accepts its own loads`() {
        assertTrue(GroupedDisplay.isStaleEpoch(loaded = 1, current = 2))
        assertFalse(GroupedDisplay.isStaleEpoch(loaded = 2, current = 2))
    }
}
