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

package deckers.thibault.aves.features.live_wallpaper_refill

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** The native bounds must match Dart's `WallpaperAdvanceInterval`. */
class AutoAdvanceIntervalTest {
    @Test
    fun clampsOffAndTooShort() {
        assertEquals(0, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(-10))
        assertEquals(0, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(0))
        assertEquals(3, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(1))
        assertEquals(3, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(2))
        assertEquals(3, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(3))
    }

    @Test
    fun keepsValuesInRange() {
        assertEquals(900, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(900))
        assertEquals(
            LiveWallpaperRefillScheduler.AutoAdvanceInterval.MAX_SECONDS,
            LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(LiveWallpaperRefillScheduler.AutoAdvanceInterval.MAX_SECONDS),
        )
    }

    @Test
    fun clampsValuesBeyondThirtyDays() {
        val max = LiveWallpaperRefillScheduler.AutoAdvanceInterval.MAX_SECONDS
        assertEquals(max, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(max + 1))
        assertEquals(max, LiveWallpaperRefillScheduler.AutoAdvanceInterval.clamp(Int.MAX_VALUE))
    }
}
