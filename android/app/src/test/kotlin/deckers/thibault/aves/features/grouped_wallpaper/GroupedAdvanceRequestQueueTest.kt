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
 * A burst of double taps must each count, but an old one must never land long
 * after the user made it, so the window is pinned down here.
 */
class GroupedAdvanceRequestQueueTest {
    @Test
    fun `requests are served in order`() {
        val queue = GroupedAdvanceRequestQueue()
        queue.request(0)
        queue.request(100)
        assertEquals(2, queue.size)
        assertTrue(queue.consume(200))
        assertTrue(queue.consume(200))
        assertFalse(queue.consume(200))
    }

    @Test
    fun `a full buffer drops the oldest request`() {
        val queue = GroupedAdvanceRequestQueue(capacity = 2)
        queue.request(0)
        queue.request(100)
        queue.request(200)
        assertEquals(2, queue.size)
        // The first tap was dropped, so the two newest are the ones replayed.
        assertTrue(queue.consume(300))
        assertTrue(queue.consume(300))
        assertFalse(queue.consume(300))
    }

    @Test
    fun `an expired request is dropped instead of replayed`() {
        val queue = GroupedAdvanceRequestQueue(timeoutMs = 3_000)
        queue.request(0)
        assertFalse(queue.consume(3_001))
        assertTrue(queue.isEmpty)
    }

    @Test
    fun `an expired request does not discard a fresh one behind it`() {
        val queue = GroupedAdvanceRequestQueue(timeoutMs = 3_000)
        queue.request(0)
        queue.request(3_500)
        assertTrue(queue.consume(4_000))
        assertEquals(0, queue.size)
    }

    @Test
    fun `the default window covers one bake but not more`() {
        val queue = GroupedAdvanceRequestQueue()
        queue.request(0)
        assertTrue(queue.consume(GroupedAdvanceRequestQueue.DEFAULT_TIMEOUT_MS))
    }

    @Test
    fun `clear drops every request`() {
        val queue = GroupedAdvanceRequestQueue()
        queue.request(0)
        queue.clear()
        assertTrue(queue.isEmpty)
        assertFalse(queue.consume(0))
    }

    @Test
    fun `a zero capacity queue drops every request`() {
        val queue = GroupedAdvanceRequestQueue(capacity = 0)
        queue.request(0)
        assertTrue(queue.isEmpty)
    }
}
