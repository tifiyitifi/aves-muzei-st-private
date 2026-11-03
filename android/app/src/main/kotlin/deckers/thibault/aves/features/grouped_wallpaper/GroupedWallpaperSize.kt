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
 * Picks the pixel size a frame is baked for.
 *
 * The wallpaper manager's desired size is not the screen: some launchers report
 * a square canvas there (2340x2340 on MIUI for a 1080x2340 display). Baking for
 * a square told the engine that every photo already matched the surface, so no
 * photo was ever turned and the image fit was judged against a square. The
 * renderer's own surface is the pixels the user sees, the display size is the
 * next best answer when no wallpaper is attached, and the manager's hint is the
 * last resort for a host that cannot report a display at all.
 *
 * Pure so the priority order is testable on the host JVM.
 */
object GroupedWallpaperSize {
    fun pick(
        surfaceWidth: Int,
        surfaceHeight: Int,
        displayWidth: Int,
        displayHeight: Int,
        desiredWidth: Int,
        desiredHeight: Int,
    ): Pair<Int, Int> = when {
        surfaceWidth > 0 && surfaceHeight > 0 -> surfaceWidth to surfaceHeight
        displayWidth > 0 && displayHeight > 0 -> displayWidth to displayHeight
        else -> desiredWidth to desiredHeight
    }
}
