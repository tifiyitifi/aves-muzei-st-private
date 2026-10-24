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
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** `AdvanceRequestQueue`: a double-tap burst must not lose any tap. */
class AdvanceRequestQueueTest {
    @Test
    fun `a burst is replayed one request at a time`() {
        val queue = AdvanceRequestQueue()

        queue.request(0)
        queue.request(200)
        queue.request(400)

        assertEquals(3, queue.size)
        assertTrue(queue.consume(1_000))
        assertTrue(queue.consume(1_000))
        assertTrue(queue.consume(1_000))
        assertFalse(queue.consume(1_000))
    }

    @Test
    fun `only the newest requests survive a full buffer`() {
        val queue = AdvanceRequestQueue(capacity = 2)

        queue.request(0)
        queue.request(100)
        queue.request(200)

        assertEquals(2, queue.size)
        assertTrue(queue.consume(300))
        assertTrue(queue.consume(300))
        assertFalse(queue.consume(300))
    }

    @Test
    fun `an expired request is dropped instead of advancing later`() {
        val queue = AdvanceRequestQueue(timeoutMs = 1_000)

        queue.request(0)

        assertFalse(queue.consume(1_001))
        assertTrue(queue.isEmpty)
    }

    @Test
    fun `expired requests are skipped but a fresh one still counts`() {
        val queue = AdvanceRequestQueue(timeoutMs = 1_000)

        queue.request(0)
        queue.request(5_000)

        assertTrue(queue.consume(5_500))
        assertTrue(queue.isEmpty)
    }

    @Test
    fun `clearing drops the buffered taps`() {
        val queue = AdvanceRequestQueue()

        queue.request(0)
        queue.clear()

        assertTrue(queue.isEmpty)
        assertFalse(queue.consume(1))
    }
}
