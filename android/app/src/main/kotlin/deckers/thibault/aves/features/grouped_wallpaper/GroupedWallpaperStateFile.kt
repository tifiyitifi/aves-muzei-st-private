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

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * What the native side needs from the Dart-owned `state.json`.
 *
 * Only the fields the renderer and the notification use are read; everything is
 * optional so a file written by a newer build, or truncated by a crash, leaves
 * the wallpaper on its placeholder instead of crashing the service.
 */
data class GroupedWallpaperFileState(
    val generation: Int,
    val status: String,
    val groupId: String,
    val groupNumber: Int,
    val groupName: String,
    val count: Int,
    val entryId: Int?,
    val entryTitle: String,
    val photo: String,
) {
    /** Whether there is a frame to draw. A locked group keeps showing its photo. */
    val hasPhoto: Boolean
        get() = (status == STATUS_READY || status == STATUS_LOCKED) && photo.isNotEmpty()

    companion object {
        const val STATUS_READY = "ready"
        const val STATUS_LOCKED = "locked"
        const val STATUS_EMPTY_GROUP = "emptyGroup"
        const val STATUS_UNAVAILABLE = "unavailable"
    }
}

/**
 * The shared directory of the grouped wallpaper.
 *
 * It is separate from Muzei's `filesDir/muzei_wallpaper`, so the two live
 * wallpapers can never read each other's state, and it is created on demand so
 * the renderer can run before Flutter ever wrote a frame.
 */
object GroupedWallpaperStateFile {
    private const val TAG = "AvesGroupedWallpaper"

    const val DIR_NAME = "grouped_wallpaper"
    const val STATE_FILE_NAME = "state.json"

    fun root(context: Context): File = File(context.filesDir, DIR_NAME)

    fun stateFile(context: Context): File = File(root(context), STATE_FILE_NAME)

    fun ensureRoot(context: Context): File {
        val root = root(context)
        if (!root.exists()) root.mkdirs()
        return root
    }

    /** Resolves the baked photo of [state], or null when there is nothing to draw. */
    fun photoFile(context: Context, state: GroupedWallpaperFileState?): File? {
        if (state == null || !state.hasPhoto) return null
        val file = File(root(context), state.photo)
        return file.takeIf { it.isFile }
    }

    fun read(context: Context): GroupedWallpaperFileState? {
        val file = stateFile(context)
        if (!file.isFile) return null
        return try {
            val raw = file.readText()
            if (raw.isBlank()) return null
            val json = JSONObject(raw)
            if (json.optInt("version", -1) != 1) {
                Log.w(TAG, "ignoring state.json of another version")
                return null
            }
            val status = json.optString("status", "")
            if (status.isEmpty()) return null
            GroupedWallpaperFileState(
                generation = json.optInt("generation", 0),
                status = status,
                groupId = json.optString("groupId", ""),
                groupNumber = json.optInt("groupNumber", 0),
                groupName = json.optString("groupName", ""),
                count = json.optInt("count", 0),
                entryId = if (json.has("entryId") && !json.isNull("entryId")) json.optInt("entryId", -1).takeIf { it >= 0 } else null,
                entryTitle = json.optString("entryTitle", ""),
                photo = json.optString("photo", ""),
            )
        } catch (e: Exception) {
            // A half-written file must never take the wallpaper service down.
            Log.w(TAG, "failed to read state.json", e)
            null
        }
    }
}
