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
 * How many baked frames the renderer keeps on the GPU.
 *
 * The frame on screen is always kept, whatever the switch says: dropping it is
 * what shows the grey placeholder. The switch only decides whether the
 * neighbours that make a tap instant are worth their memory.
 */
enum class GroupedFrameRetention {
    /** Follow the home scroll effect: its frames are the widest to keep. */
    AUTO,

    /** Keep the current, previous and next frames. */
    ALL,

    /** Keep the frame on screen only; a tap decodes its target first. */
    DISPLAYED,
    ;

    /**
     * Whether the neighbours may be evicted.
     *
     * [scrollEffect] makes a frame `surface.height × aspect` wide (up to the
     * baker's 4096 limit) instead of the surface itself, so on that layout two
     * extra frames are the expensive case `AUTO` exists for.
     */
    fun limitsNeighbours(scrollEffect: Boolean): Boolean = when (this) {
        AUTO -> scrollEffect
        ALL -> false
        DISPLAYED -> true
    }

    companion object {
        /**
         * What a file written before the switch existed gets.
         *
         * Those builds decoded and kept every slot, so keeping them is both the
         * faithful default and the one that makes a tap instant.
         */
        val DEFAULT = ALL

        /** Reads the name written by the app, falling back to [DEFAULT]. */
        fun parse(value: String?): GroupedFrameRetention =
            entries.firstOrNull { it.name.equals(value, ignoreCase = true) } ?: DEFAULT
    }
}
