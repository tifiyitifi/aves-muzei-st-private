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
import org.junit.jupiter.api.io.TempDir
import java.io.File

/**
 * The native writer's two decisions that can silently corrupt a frame: the size
 * to decode for a rotated photo, and which paths it may write.
 */
class GroupedFrameMathTest {
    @Test
    fun `an upright target is requested as is`() {
        assertEquals(3120 to 2340, FrameDecodeSize.beforeRotation(3120, 2340, rotationDegrees = 0))
        assertEquals(3120 to 2340, FrameDecodeSize.beforeRotation(3120, 2340, rotationDegrees = 180))
    }

    @Test
    fun `a quarter turn swaps the requested sides`() {
        // Glide crops in the stored orientation, so the sides are swapped before
        // the post-decode rotation makes the frame upright again.
        assertEquals(2340 to 3120, FrameDecodeSize.beforeRotation(3120, 2340, rotationDegrees = 90))
        assertEquals(2340 to 3120, FrameDecodeSize.beforeRotation(3120, 2340, rotationDegrees = 270))
    }

    @Test
    fun `a frame path inside the root is allowed`(@TempDir root: File) {
        assertTrue(FrameOutputPath.isInside(root, File(root, "frames/1/100x100/photo.webp")))
    }

    @Test
    fun `a sibling directory that shares the prefix is refused`(@TempDir temp: File) {
        val root = File(temp, "root")
        root.mkdirs()
        assertFalse(FrameOutputPath.isInside(root, File(temp, "root2/photo.webp")))
    }

    @Test
    fun `a path that escapes the root is refused`(@TempDir root: File) {
        assertFalse(FrameOutputPath.isInside(root, File(root, "../photo.webp")))
    }

    @Test
    fun `the root itself is not a frame path`(@TempDir root: File) {
        assertFalse(FrameOutputPath.isInside(root, root))
    }
}
