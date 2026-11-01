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

/** The slot a reload settles on, and why. */
data class GroupedDisplayDecision(
    /** The slot to draw now; `-1` means nothing is drawable. */
    val displayed: Int,
    /** The slot the state wants; kept while [displayed] is only a stand-in. */
    val desired: Int,
    /**
     * [displayed] is a neighbour because [desired] had no texture yet.
     *
     * A fallback is temporary by contract: the next reload that brings
     * [desired] back must restore it instead of settling on the neighbour.
     */
    val fallback: Boolean,
    /** [desired] is still missing, so the caller may schedule another reload. */
    val retry: Boolean,
)

/**
 * Decides which uploaded slot the renderer draws after a reload.
 *
 * The renderer used to move `displayed` to the state's current slot only when the
 * state was newer, then fall back to a neighbour when that slot had no texture.
 * The fallback stuck: a later reload could not tell it apart from a deliberate
 * local promotion, so a surface rebuild left the wallpaper on the previous photo
 * for good. Splitting the intent ([desired]) from what is really drawn
 * ([displayed]) makes the fallback reversible.
 *
 * Pure logic on purpose: the GL renderer only uploads what this returns.
 */
object GroupedDisplay {
    fun decide(
        stateCurrent: Int,
        statePrevious: Int,
        stateNext: Int,
        displayed: Int,
        desired: Int,
        fallback: Boolean,
        /** The state is a generation the renderer has not adopted yet. */
        fresh: Boolean,
        drawable: Set<Int>,
    ): GroupedDisplayDecision {
        // A new generation, or the first load, names what the state wants.
        // Otherwise the recorded intent stands, so a local promotion the state
        // has not caught up with is not undone.
        val intent = if (fresh || desired < 0) stateCurrent else desired
        val intentDrawable = intent >= 0 && intent in drawable
        if (intentDrawable && (fresh || fallback)) {
            // A new state wins, and a stand-in steps aside the moment the frame
            // it stood in for is uploaded.
            return GroupedDisplayDecision(displayed = intent, desired = intent, fallback = false, retry = false)
        }
        val shown = if (displayed >= 0 && displayed in drawable) {
            displayed
        } else {
            // Nothing is on screen (first load, or the context was rebuilt), so
            // take the state's order. A frame that failed to decode must not
            // blank the wallpaper: the neighbours are the next best thing.
            listOf(stateCurrent, statePrevious, stateNext, displayed).firstOrNull { it >= 0 && it in drawable } ?: -1
        }
        return GroupedDisplayDecision(
            displayed = shown,
            desired = intent,
            fallback = shown >= 0 && shown != intent,
            retry = !intentDrawable && intent >= 0,
        )
    }

    /**
     * Whether a loaded state is older than the one already on screen.
     *
     * A reload can race a writer: the file it read may predate the state the
     * renderer adopted. Adopting it would make retention treat the newer slots
     * as garbage.
     */
    fun isStaleGeneration(loaded: Int, known: Int): Boolean = loaded < known

    /**
     * Whether a loaded frame belongs to a surface that no longer exists.
     *
     * The EGL context rebuilds invalidate every texture id, so the "already
     * uploaded" snapshot a reload took before the rebuild describes nothing.
     */
    fun isStaleEpoch(loaded: Int, current: Int): Boolean = loaded != current
}
