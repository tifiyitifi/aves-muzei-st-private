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
import org.junit.jupiter.api.Test

/**
 * The frames a reload keeps are the whole difference between an instant step and
 * a wallpaper that drops to the placeholder, so the rule is pinned down here.
 */
class GroupedTextureRetentionTest {
    private fun slot(entryId: Int, photo: String = "home-$entryId.png") = entryId to photo

    @Test
    fun `frames this reload did not decode survive`() {
        val uploaded = mapOf(0 to slot(10), 1 to slot(20), 2 to slot(30))
        // Only the neighbour was decoded; the loader skipped the other two.
        val desired = mapOf(0 to slot(10), 1 to slot(20), 2 to slot(30))
        assertEquals(emptySet<Int>(), GroupedTextureRetention.staleIds(uploaded, desired, protected = setOf(1)))
    }

    @Test
    fun `a slot that left the queue is dropped`() {
        val uploaded = mapOf(0 to slot(10), 1 to slot(20), 2 to slot(30))
        val desired = mapOf(0 to slot(10), 1 to slot(20))
        assertEquals(setOf(2), GroupedTextureRetention.staleIds(uploaded, desired, protected = setOf(1)))
    }

    @Test
    fun `a slot that changed entry or effect file is dropped`() {
        val uploaded = mapOf(0 to slot(10), 1 to slot(20, "lock-20.png"))
        val desired = mapOf(0 to slot(11), 1 to slot(20, "home-20.png"))
        assertEquals(setOf(0, 1), GroupedTextureRetention.staleIds(uploaded, desired, protected = emptySet()))
    }

    @Test
    fun `the slot on screen is never dropped`() {
        // The state no longer names it, but nothing would replace it.
        val uploaded = mapOf(0 to slot(10), 1 to slot(20))
        val desired = mapOf(1 to slot(20))
        assertEquals(setOf(0), GroupedTextureRetention.staleIds(uploaded, desired, protected = emptySet()))
        assertEquals(emptySet<Int>(), GroupedTextureRetention.staleIds(uploaded, desired, protected = setOf(0)))
    }

    @Test
    fun `an empty state keeps only the protected frames`() {
        val uploaded = mapOf(0 to slot(10), 1 to slot(20))
        assertEquals(setOf(1), GroupedTextureRetention.staleIds(uploaded, emptyMap(), protected = setOf(0)))
    }
}
