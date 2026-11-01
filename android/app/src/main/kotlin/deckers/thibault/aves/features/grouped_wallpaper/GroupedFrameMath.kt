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
