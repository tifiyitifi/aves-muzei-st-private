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
 * `GroupedWallpaperViewport`: the pan window for the aspect a baked frame really
 * has.
 *
 * Frames are baked for the surface, so on a portrait phone the non-panning frame
 * is portrait too. Treating it as square (the old clamp) sampled a horizontal
 * window out of a frame that already matched the view, which cropped the sides of
 * every wallpaper with the scroll effect off.
 */
class GroupedWallpaperViewportTest {
    private val coords = FloatArray(8)
    private val tallViewAspect = 1080f / 2340f

    @Test
    fun `a frame that matches the view shows all of it`() {
        GroupedWallpaperViewport.texCoords(coords, textureAspect = tallViewAspect, viewAspect = tallViewAspect, offsetX = 0.5f)

        assertEquals(0f, coords[0], 0.0001f, "u0")
        assertEquals(1f, coords[2], 0.0001f, "u1")
        assertEquals(1f, coords[1], 0.0001f, "v1")
        assertEquals(0f, coords[5], 0.0001f, "v0")
    }

    @Test
    fun `a wide frame pans a horizontal window`() {
        GroupedWallpaperViewport.texCoords(coords, textureAspect = 1.5f, viewAspect = tallViewAspect, offsetX = 0f)
        assertEquals(0f, coords[0], 0.0001f, "left edge")
        assertEquals(tallViewAspect / 1.5f, coords[2], 0.0001f, "window width")

        GroupedWallpaperViewport.texCoords(coords, textureAspect = 1.5f, viewAspect = tallViewAspect, offsetX = 1f)
        assertEquals(1f - tallViewAspect / 1.5f, coords[0], 0.0001f, "right edge start")
        assertEquals(1f, coords[2], 0.0001f, "right edge end")
    }

    @Test
    fun `a portrait frame on a wide view crops vertically and ignores the offset`() {
        GroupedWallpaperViewport.texCoords(coords, textureAspect = 0.75f, viewAspect = 1.5f, offsetX = 0.5f)

        assertEquals(0f, coords[0], 0.0001f, "u0")
        assertEquals(1f, coords[2], 0.0001f, "u1")
        assertEquals(0.75f, coords[1], 0.0001f, "v1 at the bottom vertex")
        assertEquals(0.25f, coords[5], 0.0001f, "v0 at the top vertex")
    }

    @Test
    fun `a square frame still crops on a tall screen`() {
        // Frames baked before the surface fix are square and keep drawing as they
        // always did, until the layout change re-bakes them.
        GroupedWallpaperViewport.texCoords(coords, textureAspect = 1f, viewAspect = tallViewAspect, offsetX = 0.5f)

        val width = tallViewAspect
        assertEquals((1f - width) / 2f, coords[0], 0.0001f, "u0")
        assertEquals(1f - (1f - width) / 2f, coords[2], 0.0001f, "u1")
    }
}
