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

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** One slot's files, as recorded in `state.json`. */
data class WallpaperSlotFiles(
    val id: Int,
    val entryId: Int,
    val sharp: String,
    val effectsHome: String,
    val effectsLock: String,
) {
    /**
     * The effect image for the surface being drawn.
     *
     * The baker may reuse the sharp PNG for an identity effect and always writes
     * both files, so a missing one falls back to the other surface rather than
     * dropping the effect entirely.
     */
    fun effectFor(lockScreen: Boolean): String? {
        val path = if (lockScreen) {
            effectsLock.ifEmpty { effectsHome }
        } else {
            effectsHome.ifEmpty { effectsLock }
        }
        return path.ifEmpty { null }
    }
}

/** The slots, generation and gestures the renderer needs from `state.json`. */
data class WallpaperFileState(
    val generation: Int,
    val current: Int,
    val next: Int,
    val next2: Int,
    val slots: Map<Int, WallpaperSlotFiles>,
    val doubleTapAction: String,
    val threeFingerAction: String,
) {
    /**
     * The slot to draw.
     *
     * A native advance promotes `next` and records it in `runtime.json` before
     * Dart adopts it, so a runtime that matches this generation wins over the
     * state; a stale runtime (older generation) is ignored.
     */
    fun displaySlot(runtime: WallpaperRuntime?): WallpaperSlotFiles? {
        val runtimeCurrent = runtime?.takeIf { it.generation == generation }?.current
        if (runtimeCurrent != null) slots[runtimeCurrent]?.let { return it }
        return slots[current]
    }

    /**
     * The slot a tap would promote while [slotId] is shown.
     *
     * The state is a queue `current -> next -> next2`: a runtime advance only
     * moves the displayed slot, so the slot after *that* one is the promotable
     * spare. Deriving it here keeps a reload during a crossfade from dropping
     * the deeper spare the second tap needs.
     */
    fun promotableAfter(slotId: Int): Int = when (slotId) {
        current -> next
        next -> next2
        else -> -1
    }
}

/**
 * Reads the Dart-owned wallpaper state and writes the native-owned runtime.
 *
 * Mirrors `lib/features/muzei_wallpaper/services/wallpaper_state_store.dart`:
 * the same root, atomic writes and tolerant parsing, so a truncated file from a
 * process kill can never crash the wallpaper service.
 */
class WallpaperStateStore(val root: File) {
    companion object {
        private const val TAG = "AvesLiveWallpaper"

        /** Must match `WallpaperStateStore.inAppFiles` on the Dart side. */
        const val ROOT_DIR = "muzei_wallpaper"

        const val STATE_FILE = "state.json"
        const val RUNTIME_FILE = "runtime.json"

        fun forContext(context: Context) = WallpaperStateStore(File(context.filesDir, ROOT_DIR))
    }

    val stateFile: File get() = File(root, STATE_FILE)

    val runtimeFile: File get() = File(root, RUNTIME_FILE)

    fun ensureRoot(): File {
        root.mkdirs()
        return root
    }

    fun readState(): WallpaperFileState? {
        val json = readJson(stateFile) ?: return null
        if (json.optInt("version", -1) != 1) {
            Log.w(TAG, "unsupported state version=${json.optInt("version", -1)}")
            return null
        }

        val slots = mutableMapOf<Int, WallpaperSlotFiles>()
        val rawSlots: JSONArray = json.optJSONArray("slots") ?: JSONArray()
        for (i in 0 until rawSlots.length()) {
            val slot = rawSlots.optJSONObject(i) ?: continue
            val id = slot.optInt("id", -1)
            if (id < 0 || slots.containsKey(id)) continue
            val files = slot.optJSONObject("files") ?: continue
            slots[id] = WallpaperSlotFiles(
                id = id,
                entryId = slot.optInt("entryId", 0),
                sharp = files.optString("sharp", ""),
                effectsHome = files.optString("effectsHome", ""),
                effectsLock = files.optString("effectsLock", ""),
            )
        }

        val gestures = json.optJSONObject("gestures")
        return WallpaperFileState(
            generation = json.optInt("generation", 0),
            current = json.optInt("current", -1),
            next = json.optInt("next", -1),
            // Absent in states written before the two-ahead option existed.
            next2 = json.optInt("next2", -1),
            slots = slots,
            // Must match `WallpaperGestures`' defaults on the Dart side.
            doubleTapAction = gestures?.optString("doubleTap", "temporaryDisable") ?: "temporaryDisable",
            threeFingerAction = gestures?.optString("threeFinger", "none") ?: "none",
        )
    }

    fun readRuntime(): WallpaperRuntime? {
        val json = readJson(runtimeFile) ?: return null
        return WallpaperRuntime.fromJson(json)
    }

    fun writeRuntime(runtime: WallpaperRuntime) {
        writeJsonAtomic(runtimeFile, runtime.toJson())
        Log.d(TAG, "runtime.write generation=${runtime.generation} current=${runtime.current} next=${runtime.next}")
    }

    /** Resolves a `slots/<id>/<name>` path and rejects escapes from the root. */
    fun resolve(relative: String): File? {
        val file = File(root, relative)
        return try {
            val canonicalRoot = root.canonicalFile
            val canonicalFile = file.canonicalFile
            if (!canonicalFile.path.startsWith(canonicalRoot.path + File.separator)) return null
            if (canonicalFile.isFile) canonicalFile else null
        } catch (t: Throwable) {
            Log.w(TAG, "failed to resolve state path=$relative", t)
            null
        }
    }

    private fun readJson(file: File): JSONObject? {
        if (!file.isFile) return null
        return try {
            val text = file.readText()
            if (text.isBlank()) null else JSONObject(text)
        } catch (t: Throwable) {
            Log.w(TAG, "failed to read ${file.name}", t)
            null
        }
    }

    private fun writeJsonAtomic(target: File, json: JSONObject) {
        target.parentFile?.mkdirs()
        val tmp = File(target.parentFile, "${target.name}.${System.nanoTime()}.tmp")
        try {
            tmp.writeText(json.toString())
            if (!tmp.renameTo(target)) {
                target.delete()
                if (!tmp.renameTo(target)) {
                    throw IllegalStateException("failed to replace ${target.name}")
                }
            }
        } finally {
            tmp.delete()
        }
    }
}
