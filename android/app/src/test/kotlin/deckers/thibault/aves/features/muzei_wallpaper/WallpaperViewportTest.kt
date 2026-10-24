package deckers.thibault.aves.features.muzei_wallpaper

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * `WallpaperViewport`: cover fit, launcher parallax and zoom.
 *
 * Values are derived from the 1080x2340 surface used during device testing.
 */
class WallpaperViewportTest {
    private val squareOnTallScreen = FloatArray(8)
    private val tallViewAspect = 1080f / 2340f

    @Test
    fun `a square artwork on a tall screen is center cropped horizontally`() {
        WallpaperViewport.texCoords(
            squareOnTallScreen,
            textureAspect = 1f,
            viewAspect = tallViewAspect,
            offsetX = 0.5f,
            zoom = 1f,
        )

        val visible = tallViewAspect
        assertEquals((1f - visible) / 2f, squareOnTallScreen[0], 0.0001f, "u0")
        assertEquals(1f - (1f - visible) / 2f, squareOnTallScreen[2], 0.0001f, "u1")
        assertEquals(0f, squareOnTallScreen[1], 0.0001f, "v1")
        assertEquals(1f, squareOnTallScreen[5], 0.0001f, "v0")
    }

    @Test
    fun `the launcher offset pans between both edges`() {
        WallpaperViewport.texCoords(squareOnTallScreen, 1f, tallViewAspect, offsetX = 0f, zoom = 1f)
        assertEquals(0f, squareOnTallScreen[0], 0.0001f, "left edge")
        assertEquals(tallViewAspect, squareOnTallScreen[2], 0.0001f, "window width")

        WallpaperViewport.texCoords(squareOnTallScreen, 1f, tallViewAspect, offsetX = 1f, zoom = 1f)
        assertEquals(1f - tallViewAspect, squareOnTallScreen[0], 0.0001f, "right edge start")
        assertEquals(1f, squareOnTallScreen[2], 0.0001f, "right edge end")
    }

    @Test
    fun `an out of range offset is clamped`() {
        WallpaperViewport.texCoords(squareOnTallScreen, 1f, tallViewAspect, offsetX = -2f, zoom = 1f)
        assertEquals(0f, squareOnTallScreen[0], 0.0001f)

        WallpaperViewport.texCoords(squareOnTallScreen, 1f, tallViewAspect, offsetX = 3f, zoom = 1f)
        assertEquals(1f - tallViewAspect, squareOnTallScreen[0], 0.0001f)
    }

    @Test
    fun `a wide screen crops vertically and ignores the offset`() {
        WallpaperViewport.texCoords(squareOnTallScreen, 1f, viewAspect = 2f, offsetX = 0.5f, zoom = 1f)

        assertEquals(0f, squareOnTallScreen[0], 0.0001f, "u0")
        assertEquals(1f, squareOnTallScreen[2], 0.0001f, "u1")
        assertEquals(0.25f, squareOnTallScreen[1], 0.0001f, "v1")
        assertEquals(0.75f, squareOnTallScreen[5], 0.0001f, "v0")
    }

    @Test
    fun `zoom narrows the visible window around its center`() {
        WallpaperViewport.texCoords(squareOnTallScreen, 1f, tallViewAspect, offsetX = 0.5f, zoom = 0f)

        val width = tallViewAspect / WallpaperViewport.MAX_ZOOM_SCALE
        assertEquals(0.5f - width / 2f, squareOnTallScreen[0], 0.0001f, "u0")
        assertEquals(0.5f + width / 2f, squareOnTallScreen[2], 0.0001f, "u1")
    }

    @Test
    fun `the zoom scale follows Muzei's 1 to 1_1 range`() {
        assertEquals(1f, WallpaperViewport.zoomScale(1f), 0.0001f)
        assertEquals(1.1f, WallpaperViewport.zoomScale(0f), 0.0001f)
        assertEquals(1.1f, WallpaperViewport.zoomScale(-1f), 0.0001f)
        assertEquals(1f, WallpaperViewport.zoomScale(2f), 0.0001f)
    }
}
