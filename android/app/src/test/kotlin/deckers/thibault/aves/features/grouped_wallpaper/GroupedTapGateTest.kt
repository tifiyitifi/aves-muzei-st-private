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

import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The tap gate is what keeps a single tap from advancing the wallpaper, so its
 * windows are pinned down here rather than only on a device.
 */
class GroupedTapGateTest {
    private var now = 0L

    private fun gate() = GroupedTapGate(clock = { now })

    @Test
    fun `a single tap never fires`() {
        val gate = gate()
        assertFalse(gate.onTapSignal())
    }

    @Test
    fun `two signals inside the window fire once`() {
        val gate = gate()
        assertFalse(gate.onTapSignal())
        now += 120
        assertTrue(gate.onTapSignal())
    }

    @Test
    fun `the third signal of one gesture is dropped`() {
        val gate = gate()
        assertFalse(gate.onTapSignal())
        now += 120
        assertTrue(gate.onTapSignal())
        // The launcher sends the command for the second tap too.
        now += 20
        assertFalse(gate.onTapSignal())
    }

    @Test
    fun `two taps too far apart are two single taps`() {
        val gate = gate()
        assertFalse(gate.onTapSignal())
        now += 900
        assertFalse(gate.onTapSignal())
    }

    @Test
    fun `the next gesture fires after the cooldown`() {
        val gate = gate()
        assertFalse(gate.onTapSignal())
        now += 100
        assertTrue(gate.onTapSignal())
        now += 600
        assertFalse(gate.onTapSignal())
        now += 100
        assertTrue(gate.onTapSignal())
    }

    @Test
    fun `reset forgets a pending first tap`() {
        val gate = gate()
        assertFalse(gate.onTapSignal())
        gate.reset()
        now += 100
        assertFalse(gate.onTapSignal())
    }
}
