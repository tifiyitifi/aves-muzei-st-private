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
 * `GroupedWallpaperSize`: which size wins when the three sources disagree.
 *
 * On a MIUI build the manager reports a square desired size while the renderer
 * draws a 1080x2340 surface, so the order is what keeps rotation and image fit
 * meaningful.
 */
class GroupedWallpaperSizeTest {
    @Test
    fun `the measured surface wins`() {
        assertEquals(
            1080 to 2340,
            GroupedWallpaperSize.pick(
                surfaceWidth = 1080,
                surfaceHeight = 2340,
                displayWidth = 1080,
                displayHeight = 2340,
                desiredWidth = 2340,
                desiredHeight = 2340,
            ),
        )
    }

    @Test
    fun `the display answers when no wallpaper is attached`() {
        assertEquals(
            1080 to 2340,
            GroupedWallpaperSize.pick(
                surfaceWidth = 0,
                surfaceHeight = 0,
                displayWidth = 1080,
                displayHeight = 2340,
                desiredWidth = 2340,
                desiredHeight = 2340,
            ),
        )
    }

    @Test
    fun `an unusable display leaves the manager hint`() {
        assertEquals(
            2340 to 2340,
            GroupedWallpaperSize.pick(
                surfaceWidth = 0,
                surfaceHeight = 0,
                displayWidth = 0,
                displayHeight = 0,
                desiredWidth = 2340,
                desiredHeight = 2340,
            ),
        )
    }

    @Test
    fun `a partial measurement is ignored`() {
        assertEquals(
            1080 to 2340,
            GroupedWallpaperSize.pick(
                surfaceWidth = 1080,
                surfaceHeight = 0,
                displayWidth = 1080,
                displayHeight = 2340,
                desiredWidth = 2340,
                desiredHeight = 2340,
            ),
        )
    }
}
