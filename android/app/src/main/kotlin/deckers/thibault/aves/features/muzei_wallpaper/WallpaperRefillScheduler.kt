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
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/**
 * Schedules the headless refill runs.
 *
 * Muzei can blur at draw time, so it never needs a worker; this port bakes in
 * Dart and only the page could bake, which left the wallpaper stuck once the app
 * process was gone. Taps and auto-advance now enqueue a short-lived worker that
 * boots a Flutter engine for one bake.
 *
 * WorkManager (not an alarm) because the work is deferrable and must survive
 * reboots; auto-advance is a chain of one-time runs instead of a periodic work
 * so the long Muzei intervals (up to 3 days) stay exact.
 */
object WallpaperRefillScheduler {
    private const val TAG = "AvesLiveWallpaper"

    /** Shared with [WallpaperRefillWorker] and [FlutterUtils.initFlutterEngine]. */
    const val SHARED_PREFERENCES_KEY = "muzei_wallpaper_service"
    const val PREF_CALLBACK_HANDLE_KEY = "callback_handle"
    private const val PREF_AUTO_INTERVAL = "auto_interval_seconds"

    private const val TAP_WORK_NAME = "muzei_wallpaper_tap_refill"
    private const val AUTO_WORK_NAME = "muzei_wallpaper_auto_advance"

    /** Persists the `vm:entry-point` callback handle the worker boots. */
    fun registerCallback(context: Context, callbackHandle: Long) {
        context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .edit()
            .putLong(PREF_CALLBACK_HANDLE_KEY, callbackHandle)
            .apply()
        Log.d(TAG, "refill.callback registered=${callbackHandle != 0L}")
    }

    /**
     * Starts one refill after a wallpaper tap that no running app could serve.
     *
     * `APPEND_OR_REPLACE` serializes bursts: a second tap waits for the running
     * bake instead of cancelling it, because the renderer replays its buffered
     * taps one per refill. [ensure] is used by the recovery path (a tap found no
     * prefetched slot), where a single pending run is enough and `KEEP` avoids
     * stacking one work per tap.
     *
     * Deliberately not expedited: on Android 12+ that runs the work as a
     * foreground service, which requires `getForegroundInfo()` and a
     * notification for a two-second bake. The user just tapped the wallpaper, so
     * a plain job still runs right away.
     */
    fun enqueueTapRefill(context: Context, ensure: Boolean = false) {
        val request = OneTimeWorkRequestBuilder<WallpaperRefillWorker>()
            .setInputData(workDataOf(WallpaperRefillWorker.KEY_ADVANCE to false))
            .build()
        val policy = if (ensure) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.APPEND_OR_REPLACE
        WorkManager.getInstance(context).enqueueUniqueWork(TAP_WORK_NAME, policy, request)
        Log.d(TAG, "refill.enqueue tap ensure=$ensure")
    }

    /**
     * Applies the interval chosen in the app; `0` disables auto-advance.
     *
     * Reopening the page must not restart the countdown, so an unchanged
     * interval keeps the pending run (`KEEP`) while a changed one replaces it.
     */
    fun scheduleAutoAdvance(context: Context, seconds: Int) {
        val prefs = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
        val previous = prefs.getInt(PREF_AUTO_INTERVAL, 0)
        val manager = WorkManager.getInstance(context)
        if (seconds <= 0) {
            prefs.edit().putInt(PREF_AUTO_INTERVAL, 0).apply()
            manager.cancelUniqueWork(AUTO_WORK_NAME)
            Log.d(TAG, "auto.schedule off")
            return
        }
        prefs.edit().putInt(PREF_AUTO_INTERVAL, seconds).apply()
        val request = OneTimeWorkRequestBuilder<WallpaperRefillWorker>()
            .setInputData(workDataOf(WallpaperRefillWorker.KEY_ADVANCE to true))
            .setInitialDelay(seconds.toLong(), TimeUnit.SECONDS)
            .build()
        val policy = if (previous == seconds) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE
        manager.enqueueUniqueWork(AUTO_WORK_NAME, policy, request)
        Log.d(TAG, "auto.schedule seconds=$seconds previous=$previous")
    }

    /**
     * Starts the next countdown after a run.
     *
     * The finished run still owns the unique name, so this appends rather than
     * inserts; `KEEP` would see the running work and drop the next interval.
     */
    fun rescheduleAutoAdvance(context: Context) {
        val seconds = context.getSharedPreferences(SHARED_PREFERENCES_KEY, Context.MODE_PRIVATE)
            .getInt(PREF_AUTO_INTERVAL, 0)
        if (seconds <= 0) return
        val request = OneTimeWorkRequestBuilder<WallpaperRefillWorker>()
            .setInputData(workDataOf(WallpaperRefillWorker.KEY_ADVANCE to true))
            .setInitialDelay(seconds.toLong(), TimeUnit.SECONDS)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(AUTO_WORK_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        Log.d(TAG, "auto.reschedule seconds=$seconds")
    }
}
