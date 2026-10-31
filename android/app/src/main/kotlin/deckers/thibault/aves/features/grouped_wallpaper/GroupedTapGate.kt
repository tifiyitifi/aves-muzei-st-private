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
 * Decides when the wallpaper should act on a double tap.
 *
 * A launcher reports the same physical tap twice: as a touch event, which the
 * gesture detector turns into `onDoubleTap`, and as `COMMAND_TAP`, which it sends
 * for *every* tap including a single one. Treating either signal as a double tap
 * is what made a single tap advance the wallpaper.
 *
 * So the gate counts signals instead: one signal only arms it, and a second one
 * inside the platform's double-tap window fires the gesture exactly once. A
 * single tap never fires, a real double tap fires whichever path reports second,
 * and a launcher that sends no touch events still works on its two commands.
 */
class GroupedTapGate(
    private val clock: () -> Long,
    /** The platform's double-tap timeout; `ViewConfiguration` is 300 ms. */
    private val windowMs: Long = 300L,
    /** How long one fired gesture keeps every later signal of itself silent. */
    private val cooldownMs: Long = 400L,
) {
    private var armedAt: Long? = null
    private var firedAt: Long? = null

    /**
     * Records one tap signal.
     *
     * @return whether this signal completes a double tap, i.e. the gesture should
     * run now.
     */
    fun onTapSignal(): Boolean {
        val now = clock()
        val fired = firedAt
        // The third signal of one gesture (command, touch, command) must not fire
        // a second time.
        if (fired != null && now - fired < cooldownMs) return false
        val armed = armedAt
        if (armed != null && now - armed <= windowMs) {
            armedAt = null
            firedAt = now
            return true
        }
        armedAt = now
        return false
    }

    /** Forgets a pending first tap, e.g. when the surface goes away. */
    fun reset() {
        armedAt = null
        firedAt = null
    }
}
