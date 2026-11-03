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

import java.io.File
import java.io.IOException

/**
 * Geometry of a native frame write, kept free of Android types so it can be
 * unit tested on the host.
 */
object FrameDecodeSize {
    /**
     * The size to ask Glide for, before the rotation Aves applies afterwards.
     *
     * Glide crops in the stored orientation, so a quarter turn has to swap the
     * requested sides: cropping to the display size first and rotating after
     * would cut the wrong part of the photo.
     */
    fun beforeRotation(targetWidth: Int, targetHeight: Int, rotationDegrees: Int): Pair<Int, Int> =
        if (rotationDegrees % 180 == 0) targetWidth to targetHeight else targetHeight to targetWidth
}

/** How a photo is mapped onto a surface whose aspect ratio it does not match. */
internal enum class FrameFitMode {
    FILL,
    FIT,
    STRETCH;

    companion object {
        /** Parses the name Dart sends, with FILL as the historical default. */
        fun parse(raw: String?): FrameFitMode = when (raw) {
            "fit" -> FIT
            "stretch" -> STRETCH
            else -> FILL
        }
    }
}

/** Scale and translation of one photo inside a target frame. */
internal data class FitTransform(
    val scaleX: Float,
    val scaleY: Float,
    val translateX: Float,
    val translateY: Float,
)

/**
 * The fit half of the frame geometry, mirroring Flutter's `BoxFit`:
 *
 * - [FrameFitMode.FILL] covers the target and crops the overflow (centered);
 * - [FrameFitMode.FIT] shows the whole photo and letterboxes it (centered);
 * - [FrameFitMode.STRETCH] scales each axis independently.
 *
 * The quarter turn is applied by the writer's canvas, so this object only sees
 * the target box in the rotated coordinate space. Pure so the host tests can
 * assert the numbers the reference implementation (`ImageFitPolicy`) documents.
 */
internal object FrameFit {
    fun transform(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        mode: FrameFitMode,
    ): FitTransform {
        require(sourceWidth > 0 && sourceHeight > 0) { "Source dimensions must be positive" }
        require(targetWidth > 0 && targetHeight > 0) { "Target dimensions must be positive" }

        val widthScale = targetWidth.toFloat() / sourceWidth
        val heightScale = targetHeight.toFloat() / sourceHeight
        return when (mode) {
            FrameFitMode.STRETCH -> FitTransform(
                scaleX = widthScale,
                scaleY = heightScale,
                translateX = 0f,
                translateY = 0f,
            )

            FrameFitMode.FILL -> centered(
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
                targetWidth = targetWidth,
                targetHeight = targetHeight,
                scale = maxOf(widthScale, heightScale),
            )

            FrameFitMode.FIT -> centered(
                sourceWidth = sourceWidth,
                sourceHeight = sourceHeight,
                targetWidth = targetWidth,
                targetHeight = targetHeight,
                scale = minOf(widthScale, heightScale),
            )
        }
    }

    private fun centered(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        scale: Float,
    ) = FitTransform(
        scaleX = scale,
        scaleY = scale,
        translateX = (targetWidth - sourceWidth * scale) / 2f,
        translateY = (targetHeight - sourceHeight * scale) / 2f,
    )
}

/**
 * Keeps the frame writer inside the wallpaper's own directory.
 *
 * The channel is a narrow write primitive; resolving a path it did not create
 * must never reach the rest of the app's files.
 */
object FrameOutputPath {
    fun isInside(root: File, output: File): Boolean {
        val prefix = root.canonicalFile.path + File.separator
        return try {
            output.canonicalPath.startsWith(prefix)
        } catch (e: IOException) {
            false
        }
    }
}
