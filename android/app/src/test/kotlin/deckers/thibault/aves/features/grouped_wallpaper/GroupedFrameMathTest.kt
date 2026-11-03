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
    fun `fill center-crops the overflow on the long axis`() {
        val transform = FrameFit.transform(
            sourceWidth = 400,
            sourceHeight = 200,
            targetWidth = 100,
            targetHeight = 100,
            mode = FrameFitMode.FILL,
        )

        assertEquals(0.5f, transform.scaleX, TOLERANCE)
        assertEquals(0.5f, transform.scaleY, TOLERANCE)
        assertEquals(-50f, transform.translateX, TOLERANCE)
        assertEquals(0f, transform.translateY, TOLERANCE)
    }

    @Test
    fun `fit letterboxes and centers the whole image`() {
        val transform = FrameFit.transform(
            sourceWidth = 400,
            sourceHeight = 200,
            targetWidth = 100,
            targetHeight = 100,
            mode = FrameFitMode.FIT,
        )

        assertEquals(0.25f, transform.scaleX, TOLERANCE)
        assertEquals(0.25f, transform.scaleY, TOLERANCE)
        assertEquals(0f, transform.translateX, TOLERANCE)
        assertEquals(25f, transform.translateY, TOLERANCE)
    }

    @Test
    fun `stretch scales each axis independently without translation`() {
        val transform = FrameFit.transform(
            sourceWidth = 400,
            sourceHeight = 200,
            targetWidth = 100,
            targetHeight = 100,
            mode = FrameFitMode.STRETCH,
        )

        assertEquals(0.25f, transform.scaleX, TOLERANCE)
        assertEquals(0.5f, transform.scaleY, TOLERANCE)
        assertEquals(0f, transform.translateX, TOLERANCE)
        assertEquals(0f, transform.translateY, TOLERANCE)
    }

    @Test
    fun `fit modes parse the names Dart persists`() {
        assertEquals(FrameFitMode.FILL, FrameFitMode.parse(null))
        assertEquals(FrameFitMode.FILL, FrameFitMode.parse("fill"))
        assertEquals(FrameFitMode.FIT, FrameFitMode.parse("fit"))
        assertEquals(FrameFitMode.STRETCH, FrameFitMode.parse("stretch"))
        assertEquals(FrameFitMode.FILL, FrameFitMode.parse("unknown"))
    }

    @Test
    fun `a quarter turn fits the photo into the swapped target box`() {
        // A landscape 400x200 photo rendered into a portrait 100x300 frame with a
        // clockwise quarter turn: in the rotated coordinate space the target is
        // 300x100, so the cover scale is 0.75 and the 300x150 drawing is centered
        // and cropped by the target after the rotation.
        val transform = FrameFit.transform(
            sourceWidth = 400,
            sourceHeight = 200,
            targetWidth = 300,
            targetHeight = 100,
            mode = FrameFitMode.FILL,
        )

        assertEquals(0.75f, transform.scaleX, TOLERANCE)
        assertEquals(0.75f, transform.scaleY, TOLERANCE)
        assertEquals(0f, transform.translateX, TOLERANCE)
        assertEquals(-25f, transform.translateY, TOLERANCE)
    }

    private companion object {
        const val TOLERANCE = 0.0001f
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
