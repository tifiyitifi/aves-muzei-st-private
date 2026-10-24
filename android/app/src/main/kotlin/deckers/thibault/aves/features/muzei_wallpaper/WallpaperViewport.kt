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

package deckers.thibault.aves.features.muzei_wallpaper

import kotlin.math.min

/**
 * Texture coordinates of the wallpaper quad.
 *
 * Ported from Muzei's `GLPictureSet.recomputeTransformMatrices` (Apache-2.0):
 * cover-fit the artwork, then pan it with the launcher offset and narrow it
 * with the launcher zoom. Kept free of Android/GL types so the geometry can be
 * unit tested on the JVM.
 */
object WallpaperViewport {
    /** Muzei lets the launcher zoom the wallpaper in to 1.1x. */
    const val MAX_ZOOM_SCALE = 1.1f

    /**
     * Scale applied to the visible region for a launcher [zoom] in `0..1`,
     * where 1 is fully zoomed out.
     */
    fun zoomScale(zoom: Float): Float {
        val value = zoom.coerceIn(0f, 1f)
        return 1f + (1f - value) * (MAX_ZOOM_SCALE - 1f)
    }

    /**
     * Writes the quad's texture coordinates to [out] as
     * `u0,v1, u1,v1, u0,v0, u1,v0`.
     *
     * The sampled window always covers the view (cover fit); when the artwork
     * is wider than the view it pans horizontally by [offsetX] in `0..1`, and
     * the zoom narrows the window around its center.
     */
    fun texCoords(
        out: FloatArray,
        textureAspect: Float,
        viewAspect: Float,
        offsetX: Float,
        zoom: Float,
    ) {
        require(out.size >= 8) { "expected room for four texture coordinates" }

        var u0 = 0f
        var u1 = 1f
        var v0 = 0f
        var v1 = 1f
        if (textureAspect > viewAspect) {
            val width = ((viewAspect / textureAspect) / zoomScale(zoom)).coerceIn(0.05f, 1f)
            val start = offsetX.coerceIn(0f, 1f) * (1f - width)
            u0 = start
            u1 = start + width
        } else {
            val height = ((textureAspect / viewAspect) / zoomScale(zoom)).coerceIn(0.05f, 1f)
            v0 = (1f - height) / 2f
            v1 = v0 + height
        }

        // Bitmap row 0 is the top row, so map it to the top of the quad.
        out[0] = u0
        out[1] = v1
        out[2] = u1
        out[3] = v1
        out[4] = u0
        out[5] = v0
        out[6] = u1
        out[7] = v0
    }
}
