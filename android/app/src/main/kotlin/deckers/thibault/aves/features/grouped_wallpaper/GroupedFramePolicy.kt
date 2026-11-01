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
 * Which slots a reload decodes and keeps, given the frame retention switch.
 *
 * Pure on purpose: the GL renderer owns the textures and asks this what to do,
 * so the rule that protects the frame on screen is testable without a surface.
 */
object GroupedFramePolicy {
    /**
     * The slots one reload decodes, in order.
     *
     * A limited reload decodes only [wanted] (the frame about to be shown, plus
     * a tap's target while one is queued), so the slot the user is waiting for
     * is never queued behind neighbours it is going to evict.
     */
    fun decodeOrder(slots: List<Int>, wanted: List<Int>, limitNeighbours: Boolean): List<Int> =
        if (!limitNeighbours) slots else wanted.filter { slots.contains(it) }

    /**
     * The slots that may stay uploaded after a reload.
     *
     * The limit is only applied while [intent] is really drawable: a stand-in
     * neighbour is the only alternative to the placeholder, so it must survive
     * the round that failed to decode the wanted frame.
     */
    fun retainedIds(slots: Set<Int>, intent: Int, limitNeighbours: Boolean, drawable: Set<Int>): Set<Int> =
        if (!limitNeighbours || !drawable.contains(intent)) slots else slots.intersect(setOf(intent))
}
