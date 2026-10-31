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

/** One baked photo the renderer can show. */
data class GroupedWallpaperSlotFile(
    val id: Int,
    val entryId: Int,
    val photo: String,
    /** Display name of the photo, for the notification. */
    val title: String = "",
    /** Baked home effect; empty means the sharp [photo] is used. */
    val effectHome: String = "",
    /** Baked lock effect; empty means the sharp [photo] is used. */
    val effectLock: String = "",
) {
    /** The file this slot draws on a surface, falling back to the sharp photo. */
    fun photoFor(lockScreen: Boolean): String {
        val effect = if (lockScreen) effectLock else effectHome
        return if (effect.isEmpty()) photo else effect
    }
}

/** One group of the notification rotation. */
data class GroupedWallpaperGroupFile(
    val id: String,
    val number: Int,
    val name: String,
)

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
    val current: Int,
    val next: Int,
    val next2: Int,
    val slots: List<GroupedWallpaperSlotFile>,
    val doubleTap: String,
    val threeFinger: String,
    /**
     * Whether the user lets the wallpaper show its notification bar.
     *
     * Off means no bar and no foreground service at all, not a hidden one: the
     * setting answers "may this wallpaper keep a notification around", so the
     * service must post nothing.
     */
    val notification: Boolean = true,
    /**
     * How many photos the usage history keeps; `0` means recording is off.
     *
     * The bar greys its "previous" button when this is `0`: the engine stops
     * stepping back and no new history is written, so the button would do nothing.
     */
    val historyLimit: Int = 200,
    /**
     * Whether switching the playing group is locked.
     *
     * The bar greys its previous/next group buttons: the app's own guard refuses
     * the command anyway, so an enabled button would only do nothing.
     */
    val switchLocked: Boolean = false,
    /**
     * The group the switch lock was set on, or empty when nothing is locked.
     *
     * The bar compares it with the group on screen, so a lock set elsewhere is
     * never reported as this group's own.
     */
    val switchLockedGroupId: String = "",
    /**
     * The rotation the bar cycles, in display order.
     *
     * The notification switches groups itself, so a tap changes the bar before
     * the app has baked the next frame; [name] is display text, not an ARB key.
     */
    val groups: List<GroupedWallpaperGroupFile> = emptyList(),
) {
    fun slot(id: Int): GroupedWallpaperSlotFile? = slots.firstOrNull { it.id == id }

    /** The slot to draw, or null when there is nothing to draw. */
    val currentSlot: GroupedWallpaperSlotFile?
        get() = if (status == STATUS_READY || status == STATUS_LOCKED || status == STATUS_DISABLED) slot(current) else null

    /** Whether the wallpaper may follow its group, i.e. may promote a slot. */
    val canPromote: Boolean
        get() = status == STATUS_READY && next >= 0

    companion object {
        const val STATUS_READY = "ready"
        const val STATUS_LOCKED = "locked"
        const val STATUS_DISABLED = "disabled"
        const val STATUS_EMPTY_GROUP = "emptyGroup"
        const val STATUS_UNAVAILABLE = "unavailable"

        const val ACTION_NONE = "none"
        const val ACTION_NEXT_ARTWORK = "nextArtwork"
        const val ACTION_VIEW_ARTWORK = "viewArtwork"
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
    const val RUNTIME_FILE_NAME = "runtime.json"

    /**
     * A lock tapped on the bar while the app was not listening.
     *
     * The lock itself is persisted by the app (AppMeta), which the native side
     * cannot write, so the tap is recorded here and adopted on the next start.
     */
    const val LOCK_REQUEST_FILE_NAME = "lock_request.json"

    fun root(context: Context): File = File(context.filesDir, DIR_NAME)

    fun stateFile(context: Context): File = File(root(context), STATE_FILE_NAME)

    fun runtimeFile(context: Context): File = File(root(context), RUNTIME_FILE_NAME)

    fun ensureRoot(context: Context): File {
        val root = root(context)
        if (!root.exists()) root.mkdirs()
        return root
    }

    /** Resolves a photo path of [state], or null when the file is missing. */
    fun photoFile(context: Context, photo: String): File? {
        if (photo.isEmpty()) return null
        val file = File(root(context), photo)
        return file.takeIf { it.isFile }
    }

    fun read(context: Context): GroupedWallpaperFileState? {
        val file = stateFile(context)
        if (!file.isFile) return null
        return try {
            val raw = file.readText()
            if (raw.isBlank()) return null
            val json = JSONObject(raw)
            val version = json.optInt("version", -1)
            val status = json.optString("status", "")
            if (status.isEmpty()) return null
            when (version) {
                1 -> readV1(json, status)
                2, 3, 4 -> readQueued(json, status)
                else -> {
                    Log.w(TAG, "ignoring state.json of another version")
                    null
                }
            }
        } catch (e: Exception) {
            // A half-written file must never take the wallpaper service down.
            Log.w(TAG, "failed to read state.json", e)
            null
        }
    }

    /** v1 stored one photo and no queue. */
    private fun readV1(json: JSONObject, status: String): GroupedWallpaperFileState {
        val entryId = if (json.has("entryId") && !json.isNull("entryId")) json.optInt("entryId", -1) else -1
        val photo = json.optString("photo", "")
        val slots = if (entryId >= 0 && photo.isNotEmpty()) {
            listOf(GroupedWallpaperSlotFile(id = 0, entryId = entryId, photo = photo, title = json.optString("entryTitle", "")))
        } else {
            emptyList()
        }
        return GroupedWallpaperFileState(
            generation = json.optInt("generation", 0),
            status = status,
            groupId = json.optString("groupId", ""),
            groupNumber = json.optInt("groupNumber", 0),
            groupName = json.optString("groupName", ""),
            count = json.optInt("count", 0),
            current = if (slots.isEmpty()) -1 else 0,
            next = -1,
            next2 = -1,
            slots = slots,
            doubleTap = GroupedWallpaperFileState.ACTION_NEXT_ARTWORK,
            threeFinger = GroupedWallpaperFileState.ACTION_VIEW_ARTWORK,
        )
    }

    private fun readQueued(json: JSONObject, status: String): GroupedWallpaperFileState {
        val slots = mutableListOf<GroupedWallpaperSlotFile>()
        val seen = mutableSetOf<Int>()
        val rawSlots = json.optJSONArray("slots")
        if (rawSlots != null) {
            for (i in 0 until rawSlots.length()) {
                val raw = rawSlots.optJSONObject(i) ?: continue
                val id = raw.optInt("id", -1)
                val entryId = raw.optInt("entryId", -1)
                val photo = raw.optString("photo", "")
                if (id < 0 || entryId < 0 || photo.isEmpty() || !seen.add(id)) continue
                slots.add(
                    GroupedWallpaperSlotFile(
                        id = id,
                        entryId = entryId,
                        photo = photo,
                        title = raw.optString("title", ""),
                        effectHome = raw.optString("effectHome", ""),
                        effectLock = raw.optString("effectLock", ""),
                    ),
                );
            }
        }
        val gestures = json.optJSONObject("gestures")
        val groups = mutableListOf<GroupedWallpaperGroupFile>()
        val rawGroups = json.optJSONArray("groups")
        if (rawGroups != null) {
            for (i in 0 until rawGroups.length()) {
                val raw = rawGroups.optJSONObject(i) ?: continue
                val id = raw.optString("id", "")
                if (id.isEmpty()) continue
                groups.add(
                    GroupedWallpaperGroupFile(
                        id = id,
                        number = raw.optInt("number", 0),
                        name = raw.optString("name", ""),
                    ),
                )
            }
        }
        return GroupedWallpaperFileState(
            generation = json.optInt("generation", 0),
            status = status,
            groupId = json.optString("groupId", ""),
            groupNumber = json.optInt("groupNumber", 0),
            groupName = json.optString("groupName", ""),
            count = json.optInt("count", 0),
            current = json.optInt("current", -1),
            next = json.optInt("next", -1),
            next2 = json.optInt("next2", -1),
            slots = slots,
            doubleTap = gestures?.optString("doubleTap", GroupedWallpaperFileState.ACTION_NEXT_ARTWORK)
                ?: GroupedWallpaperFileState.ACTION_NEXT_ARTWORK,
            threeFinger = gestures?.optString("threeFinger", GroupedWallpaperFileState.ACTION_VIEW_ARTWORK)
                ?: GroupedWallpaperFileState.ACTION_VIEW_ARTWORK,
            // A file written before the setting existed means "on", which is
            // what those builds did.
            notification = json.optBoolean("notification", true),
            historyLimit = json.optInt("historyLimit", 200),
            switchLocked = json.optBoolean("switchLocked", false),
            switchLockedGroupId = json.optString("switchLockedGroupId", ""),
            groups = groups,
        )
    }

    /**
     * Records a lock request, atomically, so the app can adopt it on the next start.
     *
     * A failed write only costs the immediate persistence: the app's own state
     * still answers the next lock tap.
     */
    fun writeLockRequest(context: Context, groupId: String) {
        try {
            val root = ensureRoot(context)
            val json = JSONObject()
                .put("groupId", groupId)
                .put("at", System.currentTimeMillis())
            val tmp = File(root, "$LOCK_REQUEST_FILE_NAME.tmp")
            tmp.writeText(json.toString())
            val target = lockRequestFile(context)
            if (!tmp.renameTo(target)) {
                target.delete()
                tmp.renameTo(target)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "failed to write $LOCK_REQUEST_FILE_NAME", t)
        }
    }

    fun lockRequestFile(context: Context): File = File(root(context), LOCK_REQUEST_FILE_NAME)

    /**
     * Records the slot the renderer promoted to.
     *
     * Dart adopts it on the next refill, so the slot the renderer left behind is
     * baked again. The generation ties the record to the state it was derived
     * from: a newer state makes the record stale and it is ignored.
     */
    fun writeRuntime(context: Context, generation: Int, current: Int, next: Int, refillRequested: Boolean) {
        try {
            val root = ensureRoot(context)
            val json = JSONObject()
                .put("generation", generation)
                .put("current", current)
                .put("next", next)
                .put("refillRequested", refillRequested)
            val tmp = File(root, "$RUNTIME_FILE_NAME.tmp")
            tmp.writeText(json.toString())
            val target = runtimeFile(context)
            if (!tmp.renameTo(target)) {
                target.delete()
                tmp.renameTo(target)
            }
        } catch (t: Throwable) {
            // A lost runtime only costs one extra bake; never fail the renderer.
            Log.w(TAG, "failed to write runtime.json", t)
        }
    }
}
