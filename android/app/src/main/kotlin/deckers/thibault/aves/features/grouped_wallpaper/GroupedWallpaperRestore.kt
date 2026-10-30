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

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.ParcelFileDescriptor
import android.util.Log

/**
 * Brings the grouped wallpaper back after the system dropped it.
 *
 * AOSP rebinds a live wallpaper component when the app's package is replaced, but
 * some OEM builds (MIUI observed) reset the wallpaper to their default instead.
 * The baked state is untouched in that case, so the only thing missing is the
 * component binding, and nothing in the app would ever restore it: the user had
 * to open the system chooser again after every update.
 *
 * Binding is silent only where the platform allows it: `SET_WALLPAPER_COMPONENT` is
 * a `signature|privileged` permission, so a normal install is refused and gets a
 * one-tap notification instead. Either way the restore is deliberately narrow: it
 * only runs when the wallpaper was in use, and never takes back a live wallpaper
 * the user picked or a static photo they set.
 */
object GroupedWallpaperRestore {
    private const val TAG = "AvesGroupedWallpaper"

    /**
     * The permission that allows binding a live wallpaper.
     *
     * It is not in the public SDK (`SET_WALLPAPER_COMPONENT`), so it is spelled out;
     * the platform keeps it at `signature|privileged` level.
     */
    private const val PERMISSION_SET_WALLPAPER_COMPONENT = "android.permission.SET_WALLPAPER_COMPONENT"

    private const val PREFERENCES_NAME = "grouped_wallpaper_restore"
    private const val KEY_HINT_SHOWN = "hintShown"

    /**
     * How long a baked state still counts as "the wallpaper was in use".
     *
     * `state.json` is only rewritten while the engine runs, so an old one means
     * the feature was left alone for a long time; restoring it after months would
     * be a surprise, and the hint is a better answer than silently taking over.
     */
    private const val MAX_AGE_MILLIS = 30L * 24 * 60 * 60 * 1000

    /**
     * Statuses that still mean the user wants the wallpaper.
     *
     * Only `disabled` opts out: the user turned the feature off. The other statuses
     * are runtime conditions (no usable photo, group unavailable) that the page
     * explains, and the user is still running the wallpaper.
     */
    private val inUseStatuses = setOf(
        GroupedWallpaperFileState.STATUS_READY,
        GroupedWallpaperFileState.STATUS_LOCKED,
        GroupedWallpaperFileState.STATUS_EMPTY_GROUP,
        GroupedWallpaperFileState.STATUS_UNAVAILABLE,
    )

    /**
     * Puts the wallpaper back if the system dropped it.
     *
     * Called when the package is replaced and when the app starts, because a
     * force-stopped package receives no `MY_PACKAGE_REPLACED` broadcast. It is
     * idempotent: while the wallpaper is still bound the first check returns.
     *
     * @return whether the wallpaper was bound again.
     */
    fun restoreIfLost(context: Context): Boolean {
        val manager = WallpaperManager.getInstance(context)
        val component = ComponentName(context, GroupedLiveWallpaperService::class.java)

        val current = try {
            manager.wallpaperInfo
        } catch (t: Throwable) {
            // Without the answer there is no safe decision: guessing could replace
            // a wallpaper the user just chose.
            Log.w(TAG, "restore.stateUnavailable", t)
            return false
        }
        if (current?.serviceName == GroupedLiveWallpaperService::class.java.name) {
            // The app is opened all the time; leave as soon as nothing is wrong.
            return false
        }
        if (!wasInUse(context)) return false
        if (current != null) {
            // Another live wallpaper is bound: the user picked it, so it is theirs.
            Log.i(TAG, "restore.skip other live wallpaper=$current")
            return false
        }
        if (hasStaticWallpaper(manager)) {
            // A static photo is the user's own choice, and the OEM's fallback is
            // distinguishable from it: after a reset the system keeps no wallpaper
            // file (verified on the target device), so this case is not ours.
            Log.i(TAG, "restore.skip static wallpaper")
            return false
        }
        if (!canBindSilently(context)) {
            // `SET_WALLPAPER_COMPONENT` is a signature|privileged permission, so a
            // normal install can never bind the component itself. The hint, with its
            // one-tap restore, is the whole answer on such builds.
            Log.i(TAG, "restore.hint silent binding needs a system permission")
            postHintOnce(context)
            return false
        }

        return try {
            bindComponent(manager, component)
            val bound = manager.wallpaperInfo?.serviceName == GroupedLiveWallpaperService::class.java.name
            Log.i(TAG, "restore.done component=$component bound=$bound")
            onWallpaperActive(context)
            true
        } catch (t: Throwable) {
            // An OEM may still refuse the component; the hint is what is left.
            Log.w(TAG, "restore.failed component=$component", t)
            postHintOnce(context)
            false
        }
    }

    /**
     * Binds [component] as the system wallpaper.
     *
     * The SDK exposes no way to do this without the user: the documented
     * `ACTION_CHANGE_LIVE_WALLPAPER` intent opens the preview screen and needs a
     * tap. The operation is also a `signature|privileged` permission, so only a
     * build that holds it reaches this call at all; reflection is the sole route to
     * the hidden method, and the caller turns any failure into the hint.
     */
    private fun bindComponent(manager: WallpaperManager, component: ComponentName) {
        val method = WallpaperManager::class.java.getMethod("setWallpaperComponent", ComponentName::class.java)
        method.invoke(manager, component)
    }

    /** Whether this install may bind a live wallpaper without asking the user. */
    private fun canBindSilently(context: Context): Boolean = try {
        context.checkSelfPermission(PERMISSION_SET_WALLPAPER_COMPONENT) == PackageManager.PERMISSION_GRANTED
    } catch (t: Throwable) {
        false
    }

    /**
     * Drops a pending hint, because the wallpaper is bound again.
     *
     * Called by the service too: re-applying the wallpaper by hand makes an old
     * "it stopped" notification stale, and a later loss must be able to hint again.
     */
    fun onWallpaperActive(context: Context) {
        GroupedWallpaperNotification.cancelRestoreHint(context)
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_HINT_SHOWN)
            .apply()
    }

    /** Whether the baked state says the wallpaper was in use, and recently so. */
    private fun wasInUse(context: Context): Boolean {
        val state = GroupedWallpaperStateFile.read(context) ?: return false
        if (state.status !in inUseStatuses) return false
        if (state.paused) return false
        val written = GroupedWallpaperStateFile.stateFile(context).lastModified()
        return System.currentTimeMillis() - written <= MAX_AGE_MILLIS
    }

    /**
     * Whether a static wallpaper is set, which is what the OEM falls back to.
     *
     * The answer is unavailable on some builds; then this reports `true`, so an
     * unknown case can only hint and never replace a photo.
     */
    private fun hasStaticWallpaper(manager: WallpaperManager): Boolean {
        var file: ParcelFileDescriptor? = null
        return try {
            file = manager.getWallpaperFile(WallpaperManager.FLAG_SYSTEM)
            file != null
        } catch (t: Throwable) {
            Log.w(TAG, "restore.wallpaperFileUnavailable", t)
            true
        } finally {
            try {
                file?.close()
            } catch (t: Throwable) {
                Log.w(TAG, "restore.wallpaperFileCloseFailed", t)
            }
        }
    }

    /**
     * Posts the hint at most once per loss.
     *
     * The user may see it on every start otherwise, and a wallpaper notification is
     * not important enough to nag about.
     */
    private fun postHintOnce(context: Context) {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        if (preferences.getBoolean(KEY_HINT_SHOWN, false)) return
        preferences.edit().putBoolean(KEY_HINT_SHOWN, true).apply()
        GroupedWallpaperNotification.postRestoreHint(context)
    }
}
