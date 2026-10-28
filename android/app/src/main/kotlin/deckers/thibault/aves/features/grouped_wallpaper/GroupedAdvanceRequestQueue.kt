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

/**
 * Buffered `next photo` gestures that arrive before the next slot is baked.
 *
 * The renderer can only promote an uploaded slot, and Flutter bakes two ahead,
 * so a burst of double taps outpaces the bake. Muzei advances on every tap
 * because its provider never bakes, so silently dropping the extra taps makes
 * the gesture feel broken. Buffering keeps each tap counting: the requests are
 * replayed one by one as prefetched slots land.
 *
 * Requests expire so that a tap from a while ago never changes the wallpaper
 * long after the user made it.
 */
class GroupedAdvanceRequestQueue(
    private val capacity: Int = DEFAULT_CAPACITY,
    private val timeoutMs: Long = DEFAULT_TIMEOUT_MS,
) {
    companion object {
        /** Enough for a quick burst; more would only obscure the photo. */
        const val DEFAULT_CAPACITY = 5

        /** A bake takes a couple of seconds, so the window covers a few refills. */
        const val DEFAULT_TIMEOUT_MS = 10_000L
    }

    private val requests = ArrayDeque<Long>()

    val size: Int
        get() = requests.size

    val isEmpty: Boolean
        get() = requests.isEmpty()

    /** Records a tap, dropping the oldest request when the buffer is full. */
    fun request(now: Long) {
        if (capacity <= 0) return
        while (requests.size >= capacity) {
            requests.removeFirst()
        }
        requests.addLast(now)
    }

    /** Takes the oldest request that is still fresh, dropping the expired ones. */
    fun consume(now: Long): Boolean {
        while (requests.isNotEmpty()) {
            val requestedAt = requests.removeFirst()
            if (now - requestedAt <= timeoutMs) return true
        }
        return false
    }

    fun clear() {
        requests.clear()
    }
}
