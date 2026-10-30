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
 * a `signature|privileged` permission, so a normal install is refused. On such
 * builds the app carries the message itself ([restoreOffer] drives an in-app
 * notice; the package-replaced path also posts a one-tap notification), because an
 * OEM that resets the wallpaper also tends to silence the app's notifications.
 * Either way the restore is deliberately narrow: it only runs when the wallpaper
 * was in use, and never takes back a live wallpaper the user picked or a static
 * photo they set.
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
     * Whether the grouped wallpaper was in use and the system dropped it.
     *
     * This is the one case where offering the wallpaper back is right, so the
     * decision lives here only: the restore paths act on it, and the app asks for
     * it to show its own notice. Only the platform can tell the OEM's fallback
     * from a wallpaper the user picked, because both report the component as
     * simply not ours.
     *
     * Side-effect free, so the app can re-ask every time it comes back.
     */
    fun restoreOffer(context: Context): Boolean {
        val manager = WallpaperManager.getInstance(context)
        val current = try {
            manager.wallpaperInfo
        } catch (t: Throwable) {
            // Without the answer there is no safe decision: guessing could replace
            // a wallpaper the user just chose.
            Log.w(TAG, "restore.stateUnavailable", t)
            return false
        }
        // The app is opened all the time, so the common case has to stay cheap:
        // leave before touching the state file or the wallpaper file.
        if (current?.serviceName == GroupedLiveWallpaperService::class.java.name) return false
        // The probe is the only place that sees the platform's answer, so its
        // inputs are logged together: a reset and a wallpaper the user picked
        // are otherwise indistinguishable in a bug report.
        val inUse = wasInUse(context)
        val static = current == null && hasStaticWallpaper(manager)
        Log.i(TAG, "restore.probe current=$current inUse=$inUse static=$static")
        if (current != null) {
            // Another live wallpaper is bound: the user picked it, so it is theirs.
            return false
        }
        if (!inUse) return false
        if (static) {
            // A static photo is the user's own choice, and the OEM's fallback is
            // distinguishable from it: after a reset the system keeps no wallpaper
            // file (verified on the target device), so this case is not ours.
            return false
        }
        return true
    }

    /**
     * Puts the wallpaper back when the package was replaced and the app is not
     * open.
     *
     * The notification is the only thing that can reach the user here, so it is
     * posted when the binding is refused. Idempotent: while the wallpaper is
     * still bound [restoreOffer] returns false.
     *
     * @return whether the wallpaper was bound again.
     */
    fun restoreAfterReplace(context: Context): Boolean = restore(context, postHint = true)

    /**
     * Puts the wallpaper back when the app starts.
     *
     * No notification here: the app is being opened, and the in-app notice
     * ([restoreOffer] driving `GroupedWallpaperRestoreBody`) already offers the
     * same one tap without leaving a stale bar behind.
     *
     * @return whether the wallpaper was bound again.
     */
    fun restoreOnStart(context: Context): Boolean = restore(context, postHint = false)

    private fun restore(context: Context, postHint: Boolean): Boolean {
        if (!restoreOffer(context)) return false

        val manager = WallpaperManager.getInstance(context)
        val component = ComponentName(context, GroupedLiveWallpaperService::class.java)
        if (!canBindSilently(context)) {
            // `SET_WALLPAPER_COMPONENT` is a signature|privileged permission, so a
            // normal install can never bind the component itself. Only the
            // background path can notify; the in-app notice covers the rest.
            Log.i(TAG, "restore.hint silent binding needs a system permission")
            if (postHint) postHintOnce(context)
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
            if (postHint) postHintOnce(context)
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
